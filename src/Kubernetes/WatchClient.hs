{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Kubernetes.WatchClient
  ( WatchEvent
  , eventType
  , eventObject
  , dispatchWatch
  ) where

import Control.Monad
import Control.Monad.Trans (lift)
import Data.Aeson
import qualified Data.ByteString as B
import qualified Data.ByteString.Streaming.Char8 as Q
import Data.Function ((&))
import qualified Data.Text as T
import Kubernetes.Core
import Kubernetes.Client
import Kubernetes.MimeTypes
import Kubernetes.Model (Watch(..))
import Network.HTTP.Client


data WatchEvent a = WatchEvent
  { _eventType   :: T.Text
  , _eventObject :: a
  } deriving (Eq, Show)

instance FromJSON a => FromJSON (WatchEvent a) where
  parseJSON (Object x) = WatchEvent <$> x .: "type" <*> x .: "object"
  parseJSON _ = fail "Expected an Object"

instance ToJSON a => ToJSON (WatchEvent a) where
  toJSON x = object
    [ "type"    .= _eventType x
    , "object"  .= _eventObject x
    ]

eventType :: WatchEvent a -> T.Text
eventType = _eventType

eventObject :: WatchEvent a -> a
eventObject = _eventObject


-- | Dispatch a request setting watch to true. Takes a consumer function
-- which consumes the 'Q.ByteString' stream.
dispatchWatch ::
  (HasOptionalParam req Watch, MimeType accept, MimeType contentType) =>
    Manager
    -> KubernetesConfig
    -> KubernetesRequest req contentType resp accept
    -> (Q.ByteString IO () -> IO a)
    -> IO a
dispatchWatch manager config request apply = do
  let watchReq = applyOptionalParam request (Watch True)
  (InitRequest req) <- _toInitRequest config watchReq
  withHTTP req manager $ \resp -> responseBody resp & apply

withHTTP ::
  Request
  -> Manager
  -> (Response (Q.ByteString IO ()) -> IO a)
  -> IO a
withHTTP response manager f = withResponse response manager f'
 where
  f' resp = do
    let p = (from . brRead . responseBody) resp
    f (resp { responseBody = p })

from :: IO B.ByteString -> Q.ByteString IO ()
from io = go
 where
  go = do
    bs <- lift io
    unless (B.null bs) $ do
      Q.chunk bs
      go
