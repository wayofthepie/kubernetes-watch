{-# LANGUAGE OverloadedStrings #-}
module Main where

import Streaming (Stream, Of)
import Data.Aeson (Value)
import Data.ByteString.Char8
import qualified Streaming.Prelude as S
import Data.ByteString.Streaming.HTTP 
import qualified Data.ByteString.Streaming.Char8 as Q
import Data.JsonStream.Parser (parseByteString, value)
import Data.Function ((&))

main :: IO ()
main = do
  manager <- newManager defaultManagerSettings 
  request <- parseRequest "http://localhost:8001/api/v1/watch/endpoints"
  withHTTP request manager $ \resp -> responseBody resp
    & Q.lines
    & parseLine 
    & S.print

parseLine :: Monad m => Stream (Q.ByteString m) m r -> Stream (Of [Value]) m r
parseLine s = S.map (parseByteString value :: ByteString -> [Value]) (S.mapped Q.toStrict s)
