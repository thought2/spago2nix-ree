module Spago2Nix.Common where

import Prelude
import Data.Argonaut (class DecodeJson, Json)
import Data.Argonaut as Argonaut
import Data.Array (cons, mapWithIndex)
import Data.Bifunctor (lmap)
import Data.Codec.Argonaut (JsonCodec)
import Data.Codec.Argonaut as Codec
import Data.Either (Either)
import Data.Function.Uncurried (Fn2, runFn2)
import Data.Monoid (guard)
import Data.String (Pattern(..))
import Data.String as String
import Effect.Exception (Error)

type NixPrefetchGitResult
  = { url :: String, rev :: String, sha256 :: String }

-- ERROR STACK
--
type ErrorStack
  = Array String

printErrorStack :: ErrorStack -> String
printErrorStack errorStack =
  ([ "Something went wrong along the way..." ] <> (errorStack <#> indent))
    # String.joinWith "\n\n"
  where
  indent str =
    str
      # String.split (Pattern "\n")
      # mapWithIndex (\i line -> (if i == 0 then " - " else "   ") <> line)
      # String.joinWith "\n"

nativeErrorToStack :: Boolean -> Error -> ErrorStack
nativeErrorToStack debug unknownError =
  [ "Unknown error." ]
    <> guard debug [ show unknownError ]

-- STRING FORMATTING
--
tick :: String -> String
tick str = "`" <> str <> "`"

-- UTIL 
--
jsonParser :: String -> Either ErrorStack Json
jsonParser = Argonaut.jsonParser >>> lmap (pure >>> cons "Invalid JSON")

decodeJson :: forall a. DecodeJson a => Json -> Either ErrorStack a
decodeJson = Argonaut.decodeJson >>> lmap (pure >>> cons "Invalid JSON structure")

decode :: forall a. JsonCodec a -> Json -> Either ErrorStack a
decode codec value = Codec.decode codec value # lmap (Codec.printJsonDecodeError >>> pure)

joinSpaces :: Array String -> String
joinSpaces = String.joinWith " "

joinStrings :: Array String -> String
joinStrings = String.joinWith ""

joinNl :: Array String -> String
joinNl = String.joinWith "\n"

foreign import implStringifyPretty :: Fn2 Int Json String

stringifyPretty :: Int -> Json -> String
stringifyPretty = runFn2 implStringifyPretty
