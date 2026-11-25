{-# LANGUAGE NoRebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-missing-import-lists #-}
{-# OPTIONS_GHC -w #-}
module PackageInfo_exabyte_api (
    name,
    version,
    synopsis,
    copyright,
    homepage,
  ) where

import Data.Version (Version(..))
import Prelude

name :: String
name = "exabyte_api"
version :: Version
version = Version [0,1,0] []

synopsis :: String
synopsis = "API REST da loja de pe\231as de computador Exabyte (Yesod + PostgreSQL)"
copyright :: String
copyright = ""
homepage :: String
homepage = ""
