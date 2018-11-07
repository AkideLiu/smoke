{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Smoke.Types.Base where

import Data.Aeson
import Data.Aeson.Types (Parser, typeMismatch)
import Data.Text (Text)
import Test.Smoke.Types.Paths

data Contents a
  = Inline a
  | FileLocation Path
  deriving (Eq, Show)

parseContents :: (Text -> a) -> Value -> Parser (Contents a)
parseContents deserialize (String contents) =
  return $ Inline (deserialize contents)
parseContents deserialize (Object v) = do
  maybeContents <- v .:? "contents"
  maybeFile <- v .:? "file"
  case (maybeContents, maybeFile) of
    (Just _, Just _) -> fail "Expected \"contents\" or a \"file\", not both."
    (Just contents, Nothing) -> return $ Inline (deserialize contents)
    (Nothing, Just file) -> return $ FileLocation file
    (Nothing, Nothing) -> fail "Expected \"contents\" or a \"file\"."
parseContents _ invalid = typeMismatch "contents" invalid

newtype SuiteName = SuiteName
  { unSuiteName :: String
  } deriving (Eq, Ord, Show)

newtype TestName = TestName
  { unTestName :: String
  } deriving (Eq, Ord, Show)

newtype Executable = Executable
  { unExecutable :: Path
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
