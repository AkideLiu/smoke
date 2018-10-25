{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Test.Smoke.Types.Base where

import Data.Aeson
import Data.Text (Text)

newtype SuiteName = SuiteName
  { unSuiteName :: String
  } deriving (Eq, Ord, Show)

newtype TestName = TestName
  { unTestName :: String
  } deriving (Eq, Ord, Show)

newtype Executable = Executable
  { unExecutable :: String
  } deriving (Eq, Show, FromJSON)

newtype Command = Command
  { unCommand :: [String]
  } deriving (Eq, Show, FromJSON)

newtype Args = Args
  { unArgs :: [String]
  } deriving (Eq, Show, FromJSON)

newtype Status = Status
  { unStatus :: Int
  } deriving (Eq, Show)

newtype StdIn = StdIn
  { unStdIn :: Text
  } deriving (Eq, Show)

newtype StdOut = StdOut
  { unStdOut :: Text
  } deriving (Eq, Show)

newtype StdErr = StdErr
  { unStdErr :: Text
  } deriving (Eq, Show)
