{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Kubernetes.WatchEvent where

import Streaming (Stream, Of)
import Data.Aeson 
import qualified Streaming.Prelude as S
import Data.ByteString.Streaming.HTTP 
import qualified Data.ByteString.Streaming.Char8 as Q
import Data.JsonStream.Parser (parseByteString, Parser)
import Data.Function ((&))
import qualified Data.Text as T
import Control.Monad.IO.Class 
import Kubernetes.Core
import Kubernetes.Client
import Kubernetes.MimeTypes
import Kubernetes.Model (Watch(..))

data WatchEvent a = WatchEvent
  { typ :: T.Text
  , obj :: a
  } deriving (Eq, Show)

instance FromJSON a => FromJSON (WatchEvent a) where
  parseJSON (Object x) = WatchEvent <$> x .: "type" <*> x .: "object" 
  parseJSON _ = fail "Expected an Object"

instance ToJSON a => ToJSON (WatchEvent a) where
  toJSON x = object 
    [ "type"    .= typ x    
    , "object"  .= obj x 
    ]

-- | Dispatches a request setting watch to true.
dispatchWatch :: 
  (FromJSON a, HasOptionalParam req Watch, MimeType accept, MimeType contentType, Show a)
    => Manager 
    -> KubernetesConfig 
    -> KubernetesRequest req contentType resp accept
    -> Parser a
    -> IO ()
dispatchWatch manager config request parser = do 
  let watchReq = applyOptionalParam request (Watch True)
  (InitRequest req) <- _toInitRequest config watchReq
  withHTTP req manager $ \resp -> responseBody resp 
    & streamParse parser 
    & S.print 

streamParse ::  
  FromJSON a 
    => Parser a 
    -> Q.ByteString IO r 
    -> Stream (Of [a]) IO r
streamParse parser byteStream = do
  byteStream
    & Q.lines
    & parseEvent parser

parseEvent :: 
  (FromJSON a, Monad m) 
    => Parser a 
    -> Stream (Q.ByteString m) m r 
    -> Stream (Of [a]) m r
parseEvent parser byteStream = S.map (parseByteString parser) (S.mapped Q.toStrict byteStream)

