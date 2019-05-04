{-# LANGUAGE LambdaCase #-}

module Test.Smoke.Discovery
  ( discoverTests
  ) where

import Control.Monad (forM, unless)
import Control.Monad.Catch.Pure (runCatchT)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT(..), throwE, withExceptT)
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Vector (Vector)
import Data.Yaml
import Path
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (dropExtension)
import Test.Smoke.Errors
import Test.Smoke.Paths
import Test.Smoke.Types

type Discovery = ExceptT SmokeDiscoveryError IO

data Root
  = DirectoryRoot (Path Rel Dir)
  | FileRoot (Path Rel File)
  | SingleRoot (Path Rel File)
               TestName

discoverTests :: Options -> IO TestSpecification
discoverTests options =
  runExceptTIO $
  TestSpecification (optionsCommand options) <$>
  discoverTestsInLocations (optionsTestLocations options)

discoverTestsInLocations :: Vector String -> Discovery Suites
discoverTestsInLocations locations = do
  roots <- mapM parseRoot locations
  testsBySuite <-
    forM roots $ \case
      DirectoryRoot path -> do
        specificationFiles <- liftIO $ findFilesInPath yamlFiles path
        mapM discoverTestsInSpecificationFile specificationFiles
      FileRoot path -> return <$> discoverTestsInSpecificationFile path
      SingleRoot path selectedTestName -> do
        let (directory, suiteName) = splitSuitePath path
        suite <-
          do suite <- decodeSpecificationFile directory path
             selectedTest <-
               onNothingThrow (NoSuchTest path selectedTestName) $
               List.find ((== selectedTestName) . testName) (suiteTests suite)
             return $ suite {suiteTests = [selectedTest]}
        return [(suiteName, Right suite)]
  return $ List.sortOn fst $ concat testsBySuite

discoverTestsInSpecificationFile ::
     Path Rel File -> Discovery (SuiteName, Either SmokeDiscoveryError Suite)
discoverTestsInSpecificationFile path = do
  let (directory, suiteName) = splitSuitePath path
  suite <- decodeSpecificationFile directory path
  return (suiteName, Right suite)

splitSuitePath :: Path Rel File -> (Path Rel Dir, SuiteName)
splitSuitePath path =
  (parent path, SuiteName $ dropExtension $ toFilePath $ filename path)

decodeSpecificationFile :: Path Rel Dir -> Path Rel File -> Discovery Suite
decodeSpecificationFile directory path = do
  location <- liftIO $ resolvePath directory
  filePath <- liftIO $ toFilePath <$> resolvePath path
  withExceptT (InvalidSpecification path . prettyPrintParseException) $ do
    parsedValue <- ExceptT $ decodeFileEither filePath
    withExceptT AesonException $
      ExceptT $ return $ parseEither (parseSuite location) parsedValue

parseRoot :: String -> Discovery Root
parseRoot location = do
  let (p, s) = List.break (== '@') location
  let path = strip p
  let selectedTestName =
        if null s
          then Nothing
          else Just (TestName (strip (tail s)))
  directoryExists <- liftIO $ doesDirectoryExist path
  fileExists <- liftIO $ doesFileExist path
  unless (directoryExists || fileExists) $ throwE $ NoSuchLocation path
  parsedDir <-
    if directoryExists
      then eitherToMaybe <$> runCatchT (parseAbsOrRelDir path)
      else return Nothing
  parsedFile <-
    if fileExists
      then eitherToMaybe <$> runCatchT (parseAbsOrRelFile path)
      else return Nothing
  case (parsedDir, parsedFile, selectedTestName) of
    (Just dir, Nothing, Nothing) -> return $ DirectoryRoot dir
    (Just dir, Nothing, Just selected) ->
      throwE $ CannotSelectTestInDirectory dir selected
    (Nothing, Just file, Nothing) -> return $ FileRoot file
    (Nothing, Just file, Just selected) -> return $ SingleRoot file selected
    (_, _, _) -> throwE $ NoSuchLocation path

strip :: String -> String
strip = Text.unpack . Text.strip . Text.pack

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Left _) = Nothing
eitherToMaybe (Right value) = Just value
