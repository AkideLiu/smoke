module Test.Smoke.Plan
  ( planTests
  ) where

import Control.Applicative ((<|>))
import Control.Monad (forM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT(..), runExceptT, throwE, withExceptT)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import System.Directory (doesFileExist, findExecutable)
import Test.Smoke.Errors
import Test.Smoke.Types

type Planning = ExceptT TestPlanErrorMessage IO

type ExpectedOutputs = (Status, Vector StdOut, Vector StdErr)

planTests :: TestSpecification -> IO Plan
planTests (TestSpecification specificationCommand suites) = do
  suitePlans <-
    forM suites $ \(suiteName, Suite thisSuiteCommand tests) -> do
      let defaultCommand = thisSuiteCommand <|> specificationCommand
      testPlans <-
        forM tests $ \test ->
          runExceptT $
          withExceptT (TestPlanError test) $ do
            validateTest defaultCommand test
            readTest defaultCommand test
      return (suiteName, testPlans)
  return $ Plan suitePlans

validateTest :: Maybe Command -> Test -> Planning ()
validateTest defaultCommand test = do
  when (isNothing (testCommand test <|> defaultCommand)) $ throwE NoCommand
  when (isNothing (testArgs test) && isNothing (testStdIn test)) $
    throwE NoInput
  when (isEmpty (testStdOut test) && isEmpty (testStdErr test)) $
    throwE NoOutput
  where
    isEmpty (Fixtures fixtures) = Vector.null fixtures

readTest :: Maybe Command -> Test -> Planning TestPlan
readTest defaultCommand test = do
  (executable@(Executable executableName), args) <-
    splitCommand (testCommand test <|> defaultCommand) (testArgs test)
  executableExists <- liftIO (doesFileExist executableName)
  unless executableExists $
    onNothingThrow_ (NonExistentCommand executable) =<<
    liftIO (findExecutable executableName)
  stdIn <-
    liftIO $
    fromMaybe (StdIn Text.empty) <$> sequence (readFixture <$> testStdIn test)
  (status, stdOut, stdErr) <- liftIO $ readExpectedOutputs test
  return $
    TestPlan
      { planTest = test
      , planExecutable = executable
      , planArgs = args
      , planStdIn = stdIn
      , planStatus = status
      , planStdOut = stdOut
      , planStdErr = stdErr
      }

splitCommand :: Maybe Command -> Maybe Args -> Planning (Executable, Args)
splitCommand maybeCommand maybeArgs = do
  (executableName:commandArgs) <-
    onNothingThrow NoCommand (unCommand <$> maybeCommand)
  let args = commandArgs ++ maybe [] unArgs maybeArgs
  return (Executable executableName, Args args)

readExpectedOutputs :: Test -> IO ExpectedOutputs
readExpectedOutputs test = do
  expectedStatus <- readFixture (testStatus test)
  expectedStdOuts <- readFixtures (StdOut Text.empty) (testStdOut test)
  expectedStdErrs <- readFixtures (StdErr Text.empty) (testStdErr test)
  return (expectedStatus, expectedStdOuts, expectedStdErrs)

readFixture :: FixtureContents a => Fixture a -> IO a
readFixture (InlineFixture contents) = return contents
readFixture (FileFixture path) = deserializeFixture <$> TextIO.readFile path

readFixtures :: FixtureContents a => a -> Fixtures a -> IO (Vector a)
readFixtures defaultValue (Fixtures fixtures) =
  ifEmpty defaultValue <$> mapM readFixture fixtures
  where
    ifEmpty :: a -> Vector a -> Vector a
    ifEmpty value xs
      | Vector.null xs = Vector.singleton value
      | otherwise = xs
