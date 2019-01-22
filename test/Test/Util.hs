{-# LANGUAGE TemplateHaskell #-}

module Test.Util (
  -- * Making wai requests
    post, put, patch
  -- * Request/response quasiquoter
  , scim
  -- * JSON parsing
  , Field(..)
  , getField
  ) where

import           Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as L
import           Data.Aeson
import           Data.Aeson.Internal (JSONPathElement (Key), (<?>))
import           Data.Aeson.QQ
import           Data.Text
import           Language.Haskell.TH.Quote
import           Network.HTTP.Types
import           Network.Wai.Test (SResponse)
import           Test.Hspec.Wai hiding (post, put, patch)
import           Test.Hspec.Wai.Matcher (bodyEquals)
import           Data.Proxy
import           GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import qualified Data.HashMap.Strict as SMap

----------------------------------------------------------------------------
-- Redefine wai test helpers to include scim+json content type

post :: ByteString -> L.ByteString -> WaiSession SResponse
post path = request methodPost path [(hContentType, "application/scim+json")]

put :: ByteString -> L.ByteString -> WaiSession SResponse
put path = request methodPut path [(hContentType, "application/scim+json")]

patch :: ByteString -> L.ByteString -> WaiSession SResponse
patch path = request methodPatch path [(hContentType, "application/scim+json")]

----------------------------------------------------------------------------
-- Redefine wai quasiquoter
--
-- This code was taken from Test.Hspec.Wai.JSON and modified to accept
-- @application/scim+json@. In order to keep the code simple, we also
-- require @charset=utf-8@, even though the original implementation
-- considers it optional.

-- | A response matcher and quasiquoter that should be used instead of
-- 'Test.Hspec.Wai.JSON.json'.
scim :: QuasiQuoter
scim = QuasiQuoter
  { quoteExp = \input -> [|fromValue $(quoteExp aesonQQ input)|]
  , quotePat = const $ error "No quotePat defined for Test.Util.scim"
  , quoteType = const $ error "No quoteType defined for Test.Util.scim"
  , quoteDec = const $ error "No quoteDec defined for Test.Util.scim"
  }

class FromValue a where
  fromValue :: Value -> a

instance FromValue ResponseMatcher where
  fromValue = ResponseMatcher 200 [matchHeader] . equalsJSON
    where
      matchHeader = "Content-Type" <:> "application/scim+json;charset=utf-8"

equalsJSON :: Value -> MatchBody
equalsJSON expected = MatchBody matcher
  where
    matcher headers actualBody = case decode actualBody of
      Just actual | actual == expected -> Nothing
      _ -> let MatchBody m = bodyEquals (encode expected) in m headers actualBody

instance FromValue L.ByteString where
  fromValue = encode

instance FromValue Value where
  fromValue = id

----------------------------------------------------------------------------
-- Ad-hoc JSON parsing

-- | A way to parse out a single value from a JSON object by specifying the
-- field as a type-level string. Very useful when you don't want to create
-- extra types.
newtype Field (s :: Symbol) a = Field a
  deriving (Eq, Ord, Show, Read, Functor)

getField :: Field s a -> a
getField (Field a) = a

-- Copied from https://hackage.haskell.org/package/aeson-extra-0.4.1.1/docs/src/Data.Aeson.Extra.SingObject.html
instance (KnownSymbol s, FromJSON a) => FromJSON (Field s a) where
  parseJSON = withObject ("Field " <> show key) $ \obj ->
    case SMap.lookup key obj of
        Nothing -> fail $ "key " ++ show key ++ " not present"
        Just v  -> Field <$> parseJSON v <?> Key key
    where
      key = pack $ symbolVal (Proxy :: Proxy s)

instance (KnownSymbol s, ToJSON a) => ToJSON (Field s a) where
  toJSON (Field x) = object [ key .= x]
    where
      key = pack $ symbolVal (Proxy :: Proxy s)
