module Bluetooth.Internal.DBus where

import Control.Monad.Reader
import Data.Monoid          ((<>))
import DBus
import Lens.Micro

import qualified Data.Map  as Map
import qualified Data.Text as T

import Bluetooth.Internal.HasInterface
import Bluetooth.Internal.Interfaces
import Bluetooth.Internal.Types
import Bluetooth.Internal.Utils

-- | Registers an application and advertises it. If you would like to have
-- finer-grained control of the advertisement, use @registerApplication@ and
-- @advertise@.
registerAndAdvertiseApplication :: Application -> BluetoothM ()
registerAndAdvertiseApplication app = do
  registerApplication app
  advertise (advertisementFor app)

-- | Registers an application (set of services) with Bluez.
registerApplication :: Application -> BluetoothM ()
registerApplication app = do
  conn <- ask
  addAllObjs conn app
  toBluetoothM . const
    $ callMethod bluezName bluezPath (T.pack gattManagerIFace) "RegisterApplication"  args []
    $ dbusConn conn
  where
    args :: (ObjectPath, Map.Map T.Text Any)
    args = (app ^. path, Map.empty)

-- | Adds handlers for all the objects managed by the Application (plus the
-- Application itself).
addAllObjs :: Connection -> Application -> BluetoothM ()
addAllObjs conn app = do
  liftIO $ addObject conn (app ^. path) (app `withInterface` objectManagerIFaceP)
  liftIO $ forM_ (zip [0..] (app ^. services)) $ \(i,s) -> do
    let p = serviceObjectPath (app ^. path) i
    addObject conn p
      $  (WOP p s `withInterface` gattServiceIFaceP)
      <> (WOP p s `withInterface` propertiesIFaceP)
    forM_ (zip [0..] (s ^. characteristics)) $ \(i', c) -> do
      let p' = characteristicObjectPath p i'
      addObject conn p'
        $ (WOP p' c `withInterface` gattCharacteristicIFaceP)
       <> (WOP p' c `withInterface` propertiesIFaceP)

-- | Advertise a set of services.
advertise :: WithObjectPath Advertisement -> BluetoothM ()
advertise adv = do
  conn <- ask
  liftIO $ do
    addObject conn (adv ^. path)
      $  (adv `withInterface` leAdvertisementIFaceP)
      <> ((adv ^. value) `withInterface` propertiesIFaceP)
  toBluetoothM . const $ do
    callMethod bluezName bluezPath (T.pack leAdvertisingManagerIFace) "RegisterAdvertisement" args []
      $ dbusConn conn
  where
    args :: (ObjectPath, Map.Map T.Text Any)
    args = (adv ^. path, Map.empty)

-- | Create an advertisement for all of an application's services.
-- The advertisement will be for peripheral (not broadcast) by default.
advertisementFor :: Application -> WithObjectPath Advertisement
advertisementFor app = WOP p adv
  where
    adv = def & serviceUUIDs .~ (app ^.. services . traversed . uuid)
    p = app ^. path & toText %~ (</> "adv")

-- * Constants

bluezName :: T.Text
bluezName = "org.bluez"

bluezPath :: ObjectPath
bluezPath = "/org/bluez/hci0"