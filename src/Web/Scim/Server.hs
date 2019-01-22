module Web.Scim.Server
  (
  -- * WAI application
  app, mkapp, App

  -- * API tree
  , SiteAPI, siteServer
  -- ** API subtrees, useful for tests
  , ConfigAPI, configServer
  , UserAPI, userServer
  , GroupAPI, groupServer
  ) where

import           Web.Scim.Class.User (UserSite (..), UserDB, userServer)
import           Web.Scim.Class.Group (GroupSite (..), GroupDB, groupServer)
import           Web.Scim.Class.Auth (AuthDB (..))
import           Web.Scim.Capabilities.MetaSchema (ConfigSite, Configuration, configServer)
import           Web.Scim.Handler
import           GHC.Generics (Generic)
import           Network.Wai
import           Servant
import           Servant.API.Generic
import           Servant.Server.Generic

----------------------------------------------------------------------------
-- API specification

type DB m = (UserDB m, GroupDB m, AuthDB m)

type ConfigAPI        = ToServantApi ConfigSite
type UserAPI          = ToServantApi UserSite
type GroupAPI         = ToServantApi GroupSite
type SiteAPI authData = ToServantApi (Site authData)

data Site authData route = Site
  { config :: route :-
      ConfigAPI
  , users :: route :-
      Header "Authorization" authData :>
      "Users" :> UserAPI
  , groups :: route :-
      Header "Authorization" authData :>
      "Groups" :> GroupAPI
  } deriving (Generic)

----------------------------------------------------------------------------
-- API implementation

siteServer ::
  forall m. DB m =>
  Configuration -> Site (AuthData m) (AsServerT (ScimHandler m))
siteServer conf = Site
  { config = toServant $ configServer conf
  , users = \authData -> toServant (userServer authData)
  , groups = \authData -> toServant (groupServer authData)
  }
  where

----------------------------------------------------------------------------
-- Server-starting utilities

type App m api =
  ( DB m
  , HasServer api '[]
  )

mkapp :: forall m api. (App m api)
      => Proxy api
      -> ServerT api (ScimHandler m)
      -> (forall a. ScimHandler m a -> Handler a)
      -> Application
mkapp proxy api nt =
  serve proxy $
    hoistServer proxy nt api

app :: forall m. App m (SiteAPI (AuthData m))
    => Configuration
    -> (forall a. ScimHandler m a -> Handler a)
    -> Application
app c = mkapp (Proxy @(SiteAPI (AuthData m))) (toServant $ siteServer c)