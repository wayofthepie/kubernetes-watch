{-# LANGUAGE OverloadedStrings #-}
module Main where

import Streaming (Stream, Of)
import Data.Aeson 
import qualified Streaming.Prelude as S
import Data.ByteString.Streaming.HTTP 
import qualified Data.ByteString.Streaming.Char8 as Q
import Data.JsonStream.Parser (parseByteString, value, Parser)
import Data.Function ((&))
import qualified Data.Text as T
import Kubernetes.Model (V1Endpoints)

data WatchEvent a = WatchEvent
  { _type :: T.Text
  , _object :: a
  } deriving (Eq, Show)

instance FromJSON a => FromJSON (WatchEvent a) where
  parseJSON (Object x) = WatchEvent <$> x .: "type" <*> x .: "object" 
  parseJSON _ = fail "Expected an Object"

instance ToJSON a => ToJSON (WatchEvent a) where
  toJSON x = object 
    [ "type"    .= _type x    
    , "object"  .= _object x 
    ]


main :: IO ()
main = do
  manager <- newManager defaultManagerSettings 
  request <- parseRequest "http://localhost:8001/api/v1/watch/endpoints"
  withHTTP request manager $ \resp -> responseBody resp
    & Q.lines
    & parseLine (value :: Parser (WatchEvent V1Endpoints))
    & S.print

parseLine :: 
  (ToJSON a, Monad m) 
    => Parser a 
    -> Stream (Q.ByteString m) m r 
    -> Stream (Of [a]) m r
parseLine parser byteStream = S.map (parseByteString parser) (S.mapped Q.toStrict byteStream)
