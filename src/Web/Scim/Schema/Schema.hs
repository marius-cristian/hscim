
module Web.Scim.Schema.Schema where

import           Web.Scim.Capabilities.MetaSchema.User
import           Web.Scim.Capabilities.MetaSchema.SPConfig
import           Web.Scim.Capabilities.MetaSchema.Group
import           Web.Scim.Capabilities.MetaSchema.Schema
import           Web.Scim.Capabilities.MetaSchema.ResourceType

import           Data.Text
import           Data.Aeson

-- | All schemas that we support.
data Schema = User20
            | ServiceProviderConfig20
            | Group20
            | Schema20
            | ResourceType20
            | ListResponse2_0
            | Error2_0
  deriving (Show, Eq)

instance FromJSON Schema where
  parseJSON = withText "schema" $ \t -> case fromSchemaUri t of
    Just s  -> pure s
    Nothing -> fail "unsupported schema"

instance ToJSON Schema where
  toJSON = toJSON . getSchemaUri

-- | Get schema URI (e.g. @urn:ietf:params:scim:schemas:core:2.0:User@).
getSchemaUri :: Schema -> Text
getSchemaUri User20 =
  "urn:ietf:params:scim:schemas:core:2.0:User"
getSchemaUri ServiceProviderConfig20 =
  "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"
getSchemaUri Group20 =
  "urn:ietf:params:scim:schemas:core:2.0:Group"
getSchemaUri Schema20 =
  "urn:ietf:params:scim:schemas:core:2.0:Schema"
getSchemaUri ResourceType20 =
  "urn:ietf:params:scim:schemas:core:2.0:ResourceType"
getSchemaUri ListResponse2_0 =
  "urn:ietf:params:scim:api:messages:2.0:ListResponse"
getSchemaUri Error2_0 =
  "urn:ietf:params:scim:api:messages:2.0:Error"

-- | Get a schema by its URI.
fromSchemaUri :: Text -> Maybe Schema
fromSchemaUri s = case s of
  "urn:ietf:params:scim:schemas:core:2.0:User" ->
    pure User20
  "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig" ->
    pure ServiceProviderConfig20
  "urn:ietf:params:scim:schemas:core:2.0:Group" ->
    pure Group20
  "urn:ietf:params:scim:schemas:core:2.0:Schema" ->
    pure Schema20
  "urn:ietf:params:scim:schemas:core:2.0:ResourceType" ->
    pure ResourceType20
  "urn:ietf:params:scim:api:messages:2.0:ListResponse" ->
    pure ListResponse2_0
  "urn:ietf:params:scim:api:messages:2.0:Error" ->
    pure Error2_0
  _ ->
    Nothing

-- | Get schema description as JSON.
getSchema :: Schema -> Maybe Value
getSchema ServiceProviderConfig20 =
  pure spConfigSchema
getSchema User20 =
  pure userSchema
getSchema Group20 =
  pure groupSchema
getSchema Schema20 =
  pure metaSchema
getSchema ResourceType20 =
  pure resourceSchema
-- Schemas for these types are not in the SCIM standard
getSchema ListResponse2_0 =
  Nothing
getSchema Error2_0 =
  Nothing