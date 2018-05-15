{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE TypeOperators   #-}
{-# LANGUAGE ConstraintKinds   #-}

module Web.SCIM.Server
  ( hoistSCIM
  , SiteAPI
  , SCIMHandler
  ) where

import           Web.SCIM.Class.Group (GroupSite (..), GroupDB, groupServer)
import           Web.SCIM.Capabilities.MetaSchema (ConfigAPI, Configuration, configServer)
import           Control.Applicative ((<|>), Alternative)
import           Control.Monad.Except
import           Control.Error.Util (note)
import           Data.Text
import           Web.SCIM.Class.User (StoredUser, UserDB)
import qualified Web.SCIM.Class.User as User
import           GHC.Generics (Generic)
import           Network.Wai
import           Web.SCIM.Schema.User hiding (schemas)
import           Web.SCIM.Schema.Meta
import           Web.SCIM.Schema.Error
import           Web.SCIM.Schema.ListResponse
import           Servant
import           Servant.Generic


type SCIMHandler m = (MonadError ServantErr m, UserDB m, GroupDB m)
type SiteAPI = ToServant (Site AsApi)

data Site route = Site
  { config :: route :- ToServant (ConfigAPI AsApi)
  , users :: route :- "Users" :> ToServant (UserSite AsApi)
  , groups :: route :- "Groups" :> ToServant (GroupSite AsApi)
  } deriving (Generic)

data UserSite route = UserSite
  { getUsers :: route :-
      Get '[JSON] (ListResponse StoredUser)
  , getUser :: route :-
      Capture "id" Text :> Get '[JSON] StoredUser
  , postUser :: route :-
      ReqBody '[JSON] User :> PostCreated '[JSON] StoredUser
  , putUser :: route :-
      Capture "id" Text :> ReqBody '[JSON] User :> Put '[JSON] StoredUser
  , patchUser :: route :-
      Capture "id" Text :> Patch '[JSON] StoredUser
  , deleteUser :: route :-
      Capture "id" Text :> DeleteNoContent '[JSON] NoContent
  } deriving (Generic)


siteServer :: SCIMHandler m => UserSite (AsServerT m)
siteServer = UserSite
  { getUsers   = User.list
  , getUser    = getUser'
  , postUser   = User.create
  , putUser    = updateUser'
  , patchUser  = User.patch
  , deleteUser = deleteUser'
  }

superServer :: Configuration -> SCIMHandler m => Site (AsServerT m)
superServer conf = Site
  { config = toServant $ configServer conf
  , users = toServant siteServer
  , groups = toServant groupServer
  }

updateUser' :: SCIMHandler m => UserId -> User -> m StoredUser
updateUser' uid update = do
  -- TODO: don't fetch here, let User.update do it
  stored <- User.get uid
  case stored of
    Just (WithMeta _meta (WithId _ existing)) ->
      let newUser = existing `overwriteWith` update
      in do
        t <- User.update uid newUser
        case t of
          Left _err -> throwError err400
          Right newStored -> pure newStored
    Nothing -> throwError err400

getUser' :: SCIMHandler m => UserId -> m StoredUser
getUser' uid = do
  maybeUser <- User.get uid
  liftEither $ note (notFound uid) maybeUser

deleteUser' :: SCIMHandler m => UserId -> m NoContent
deleteUser' uid = do
    deleted <- User.delete uid
    if deleted then return NoContent else throwError err404

api :: Proxy SiteAPI
api = Proxy

{-| Similar to Servant's 'Servant.Server.hoistServer' this lets you use
  a different transformer stack than Servant's, providing a
  transformation into the Servant stack. 

  The transformation is usually simple, as the Servant stack is simply
  'IO' with 'MonadError'. For example, with `ReaderT` you simply run
  it:

  @
  type MyStack = ReaderT Env Handler

  instance SCIMHandler MyStack where
    -- TODO: implement

  transformation :: r -> ReaderT r m a -> m a
  transformation = flip runReaderT

  app :: Application
  app = hoistSCIM (env :: Env) transformation
  @

  See 'Mock' for an example of this usage.
-}
hoistSCIM :: SCIMHandler m => Configuration -> (forall a. m a -> Handler a) -> Application
hoistSCIM c t = serve (Proxy :: Proxy SiteAPI) $ hoistServer api t (toServant $ superServer c)


-- TODO: move to User.hs
overwriteWith :: User -> User -> User
overwriteWith old new = old
  { externalId = merge externalId
  , name = merge name
  , displayName = merge displayName
  , nickName = merge nickName
  , profileUrl = merge profileUrl
  , title = merge title
  , userType = merge userType
  , preferredLanguage = merge preferredLanguage
  , locale = merge locale
  , active = merge active
  , password = merge password
  , emails = mergeList emails
  , phoneNumbers = mergeList phoneNumbers
  , ims = mergeList ims
  , photos = mergeList photos
  , addresses = mergeList addresses
  , entitlements = mergeList entitlements
  , roles = mergeList roles
  , x509Certificates = mergeList x509Certificates
  }
  where
    merge :: (Alternative f) => (User -> f a) -> f a
    merge accessor = (accessor new) <|> (accessor old)

    mergeList :: (User -> Maybe [a]) -> Maybe [a]
    mergeList accessor = case accessor new of
      Just [] -> accessor old
      _ -> (accessor new) <|> (accessor old)
