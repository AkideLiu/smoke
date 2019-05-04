{-# LANGUAGE OverloadedStrings #-}

module Test.Smoke.Types.Tests where

import Data.Aeson hiding (Options)
import Data.Aeson.Types (Parser)
import Data.Vector (Vector)
import Path
import Test.Smoke.Paths
import Test.Smoke.Types.Base
import Test.Smoke.Types.Errors
import Test.Smoke.Types.Fixtures

data Options = Options
  { optionsCommand :: Maybe Command
  , optionsTestLocations :: Vector String
  } deriving (Eq, Show)

data TestSpecification =
  TestSpecification (Maybe Command)
                    Suites

type Suites = [(SuiteName, Either SmokeDiscoveryError Suite)]

data Suite = Suite
  { suiteLocation :: Path Abs Dir
  , suiteWorkingDirectory :: Maybe WorkingDirectory
  , suiteCommand :: Maybe Command
  , suiteTests :: [Test]
  } deriving (Eq, Show)

data Test = Test
  { testName :: TestName
  , testWorkingDirectory :: Maybe WorkingDirectory
  , testCommand :: Maybe Command
  , testArgs :: Maybe Args
  , testStdIn :: Maybe (Fixture StdIn)
  , testStdOut :: Fixtures StdOut
  , testStdErr :: Fixtures StdErr
  , testStatus :: Fixture Status
  } deriving (Eq, Show)

parseSuite :: Path Abs Dir -> Value -> Parser Suite
parseSuite location =
  withObject "Suite" $ \v ->
    Suite location <$>
    (parseWorkingDirectory location =<< (v .:? "working-directory")) <*>
    (v .:? "command") <*>
    (mapM (parseTest location) =<< (v .: "tests"))

parseTest :: Path Abs Dir -> Value -> Parser Test
parseTest location =
  withObject "Test" $ \v ->
    Test <$> (TestName <$> v .: "name") <*>
    (parseWorkingDirectory location =<< (v .:? "working-directory")) <*>
    (v .:? "command") <*>
    (v .:? "args") <*>
    (v .:? "stdin") <*>
    (v .:? "stdout" .!= noFixtures) <*>
    (v .:? "stderr" .!= noFixtures) <*>
    (Fixture <$> (Inline . Status <$> v .:? "exit-status" .!= 0) <*>
     return Nothing)

parseWorkingDirectory ::
     Path Abs Dir -> Maybe FilePath -> Parser (Maybe WorkingDirectory)
parseWorkingDirectory _ Nothing = return Nothing
parseWorkingDirectory location (Just filePath) =
  either (fail . show) (return . Just . WorkingDirectory) $
  location <//> filePath
