module Spago2Nix.IO (runCli) where

import Prelude
import Control.Bind (bindFlipped)
import Control.Monad.Except (ExceptT(..), lift, mapExceptT, withExceptT)
import Control.Parallel (class Parallel, parTraverse)
import Data.Argonaut (encodeJson)
import Data.Array (cons, mapWithIndex)
import Data.Array as Array
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Traversable (sequence)
import Data.TraversableWithIndex (traverseWithIndex)
import Data.Tuple.Nested ((/\))
import Effect.Aff (Aff, try)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Node.ChildProcess (Exit(..), defaultSpawnOptions)
import Node.Encoding (Encoding(..))
import Node.FS.Aff as FS
import Node.Process as Node
import Options.Applicative (execParser)
import Record (union)
import Spago2Nix.Common (ErrorStack, NixPrefetchGitResult, decodeJson, decodeMapFromObject, encodeMapToObject, joinNl, joinSpaces, joinStrings, jsonParser, stringifyPretty, tick)
import Spago2Nix.Config (CliArgs, Config, EnvVars, cliParserInfo, parseEnvVars)
import Spago2Nix.SpagoPackage (SpagoPackage)
import Sunde as Sunde

data CliState
  = CliState_Idle
  | CliState_GetConfig
  | CliState_ReadInput { path :: String }
  | CliState_NixPrefetch { index :: Int, length :: Int, spagoPackage :: SpagoPackage }
  | CliState_NixPrefetchChunk { index :: Int, chunkSize :: Int, length :: Int }
  | CliState_Format
  | CliState_WriteOutput { path :: String }
  | CliState_Done

getEnvVars :: ExceptT ErrorStack Aff { | EnvVars () }
getEnvVars =
  Node.getEnv
    # liftEffect
    <#> (parseEnvVars >>> lmap (cons "Read Environment variables."))
    # ExceptT

getCliArgs :: ExceptT ErrorStack Aff { | CliArgs () }
getCliArgs =
  execParser cliParserInfo
    # liftEffect
    # lift

getConfig :: ExceptT ErrorStack Aff Config
getConfig = union <$> getCliArgs <*> getEnvVars

spawn ::
  { cmd :: String, args :: Array String, stdin :: Maybe String } ->
  ExceptT ErrorStack Aff String
spawn options =
  -- TODO: Check why error is not catched
  Sunde.spawn options defaultSpawnOptions
    # try
    <#> case _ of
        Right { exit: Normally 0, stdout } -> Right stdout
        Right { stderr } -> Left [ stderr ]
        Left error -> Left [ "Command not found. " <> tick options.cmd ]
    <#> lmap (cons "spawn")
    # ExceptT

dhallToJson ::
  forall cfg.
  { dhallToJson :: String | cfg } -> String -> ExceptT ErrorStack Aff String
dhallToJson config dhallCode =
  spawn
    { cmd: config.dhallToJson
    , args: []
    , stdin: Just dhallCode
    }
    # withExceptT (cons "dhallToJson")

nixPrefetchGit ::
  forall cfg.
  { nixPrefetchGit :: String | cfg } ->
  { repo :: String, rev :: String } -> ExceptT ErrorStack Aff NixPrefetchGitResult
nixPrefetchGit config { repo, rev } =
  spawn
    { cmd: config.nixPrefetchGit
    , args: [ repo, "--rev", rev ]
    , stdin: Nothing
    }
    # (mapExceptT <<< map <<< bindFlipped) (jsonParser >=> decodeJson)
    # withExceptT (cons "nixPrefetchGit")

nixFormat ::
  forall cfg.
  { nixFormat :: String | cfg } ->
  { source :: String } -> ExceptT ErrorStack Aff String
nixFormat config options =
  spawn
    { cmd: config.nixFormat
    , args: []
    , stdin: Just options.source
    }
    # withExceptT (cons "nixFormat")

getSpagoPackages :: Config -> ExceptT ErrorStack Aff (Map String SpagoPackage)
getSpagoPackages config =
  dhallToJson config
    ("./" <> config.spagoPackages)
    # (mapExceptT <<< map <<< bindFlipped)
        (jsonParser >=> decodeMapFromObject decodeJson)
    # withExceptT (cons $ "Read spago config at " <> tick config.spagoPackages <> ".")

writeTextFile :: String -> String -> ExceptT ErrorStack Aff Unit
writeTextFile path content =
  try (FS.writeTextFile UTF8 path content)
    # ExceptT
    # withExceptT (const [ "Cannot write to file " <> tick path <> "." ])

setCliState :: CliState -> ExceptT ErrorStack Aff Unit
setCliState cliState = case printCliState cliState of
  Just output -> log output
  Nothing -> pure unit

withCliState :: forall a. CliState -> ExceptT ErrorStack Aff a -> ExceptT ErrorStack Aff a
withCliState cliState m = do
  setCliState cliState
  result <- m
  setCliState CliState_Idle
  pure result

runCli :: ExceptT ErrorStack Aff Unit
runCli = do
  config <-
    withCliState
      CliState_GetConfig
      getConfig
  spagoPackages <-
    withCliState
      (CliState_ReadInput { path: config.spagoPackages })
      (getSpagoPackages config)
  let
    length = Map.size spagoPackages

    chunkSize = 20
  spagoPackages
    # (Map.toUnfoldable :: _ -> Array _)
    # mapWithIndex (/\)
    # chunks chunkSize
    <#> parTraverse
        ( \(index /\ (key /\ spagoPackage)) -> do
            nixPrefetchGitResult <-
              nixPrefetchGit config
                { repo: spagoPackage.repo
                , rev: spagoPackage.version
                }
            let
              value = spagoPackage `union` nixPrefetchGitResult
            pure $ key /\ value
        )
    # traverseWithIndex
        ( \index x ->
            withCliState (CliState_NixPrefetchChunk { chunkSize, index, length })
              x
        )
    <#> join
    >>= ( \result ->
          withCliState
            (CliState_WriteOutput { path: config.target })
            ( result
                # Map.fromFoldable
                # encodeMapToObject encodeJson
                # stringifyPretty 2
                # writeTextFile config.target
            )
      )
    >>= (const $ setCliState CliState_Done)

parTraverse' :: forall m a b f. Parallel f m => { max :: Int } -> (a -> m b) -> Array a -> m (Array b)
parTraverse' { max } f xs =
  chunks max xs
    <#> parTraverse f
    # sequence
    <#> join

-- UTIL
printCliState :: CliState -> Maybe String
printCliState = case _ of
  -- TODO: Remove Maybe
  CliState_Idle -> Just "done\n"
  CliState_GetConfig -> Just "Get config"
  CliState_ReadInput { path } ->
    Just
      $ joinSpaces
          [ "Reading"
          , tick path
          ]
  CliState_NixPrefetch { index, length, spagoPackage } ->
    Just
      $ joinNl
          [ joinStrings
              [ show (index + 1)
              , "/"
              , show length
              ]
          , joinSpaces [ "fetching", tick spagoPackage.repo, "..." ]
          ]
  CliState_NixPrefetchChunk { index, chunkSize, length } ->
    Just
      $ joinSpaces
          [ "fetching chunk "
          , joinStrings
              [ show (index * chunkSize)
              , "-"
              , show $ min ((index + 1) * chunkSize) length
              , "/"
              , show length
              ]
          , "..."
          ]
  CliState_Format -> Just "Format result"
  CliState_WriteOutput { path } ->
    Just
      $ joinSpaces
          [ "Writing to"
          , tick path
          ]
  CliState_Done -> Just "done"

chunks :: forall a. Int -> Array a -> Array (Array a)
chunks n [] = []

chunks n xs = [ Array.take n xs ] <> chunks n (Array.drop n xs)
