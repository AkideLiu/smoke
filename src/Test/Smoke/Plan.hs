module Test.Smoke.Plan
  ( planTests
  ) where

import Control.Applicative ((<|>))
import Control.Monad (forM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT(..), runExceptT, throwE, withExceptT)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Text as Text
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import Path
import System.Directory (doesFileExist, findExecutable)
import System.IO.Error (isDoesNotExistError, tryIOError)
import Test.Smoke.Errors
import Test.Smoke.Filters
import Test.Smoke.Paths
import Test.Smoke.Types

type Planning = ExceptT SmokePlanningError IO

planTests :: TestSpecification -> IO Plan
planTests (TestSpecification specificationCommand suites) = do
  currentWorkingDirectory <- WorkingDirectory <$> getCurrentWorkingDirectory
  suitePlans <-
    forM suites $ \(suiteName, suite) ->
      case suite of
        Left errorMessage -> return $ SuitePlanError suiteName errorMessage
        Right (Suite location thisSuiteWorkingDirectory thisSuiteCommand tests) -> do
          let defaultCommand = thisSuiteCommand <|> specificationCommand
          let defaultWorkingDirectory =
                fromMaybe currentWorkingDirectory thisSuiteWorkingDirectory
          testPlans <-
            forM tests $ \test ->
              runExceptT $
              withExceptT (TestPlanError test) $ do
                validateTest defaultCommand test
                readTest location defaultWorkingDirectory defaultCommand test
          return $ SuitePlan suiteName location testPlans
  return $ Plan suitePlans

validateTest :: Maybe Command -> Test -> Planning ()
validateTest defaultCommand test = do
  when (isNothing (testCommand test <|> defaultCommand)) $ throwE NoCommand
  when (isNothing (testArgs test) && isNothing (testStdIn test)) $
    throwE NoInput
  when
    (isEmptyFixtures (testStdOut test) &&
     isEmptyFixtures (testStdErr test) && isEmptyFiles (testFiles test)) $
    throwE NoOutput
  where
    isEmptyFixtures (Fixtures fixtures) = Vector.null fixtures
    isEmptyFiles = Map.null

readTest ::
     Path Abs Dir
  -> WorkingDirectory
  -> Maybe Command
  -> Test
  -> Planning TestPlan
readTest location defaultWorkingDirectory defaultCommand test = do
  let workingDirectory =
        fromMaybe defaultWorkingDirectory (testWorkingDirectory test)
  executable <- convertCommandToExecutable (testCommand test <|> defaultCommand)
  let args = fromMaybe mempty (testArgs test)
  let executableName =
        case executable of
          ExecutableProgram executablePath _ -> toFilePath executablePath
          ExecutableScript (Shell shellPath _) _ -> toFilePath shellPath
  executableExists <- liftIO (doesFileExist executableName)
  unless executableExists $ do
    foundExecutable <- liftIO (findExecutable executableName)
    onNothingThrow_ (NonExistentCommand executable) foundExecutable
  unfilteredStdIn <-
    fromMaybe (Unfiltered (StdIn Text.empty)) <$>
    sequence (readFixture location <$> testStdIn test)
  stdIn <- withExceptT PlanningFilterError $ applyFilters unfilteredStdIn
  status <- unfiltered <$> readFixture location (testStatus test)
  stdOut <- Vector.map unfiltered <$> readFixtures location (testStdOut test)
  stdErr <- Vector.map unfiltered <$> readFixtures location (testStdErr test)
  files <-
    mapM (fmap (Vector.map unfiltered) . readFixtures location) (testFiles test)
  let revert = Vector.map (location </>) (testRevert test)
  return $
    TestPlan
      { planTest = test
      , planWorkingDirectory = workingDirectory
      , planExecutable = executable
      , planArgs = args
      , planStdIn = stdIn
      , planStatus = status
      , planStdOut = stdOut
      , planStdErr = stdErr
      , planFiles = files
      , planRevert = revert
      }

convertCommandToExecutable :: Maybe Command -> Planning Executable
convertCommandToExecutable Nothing = throwE NoCommand
convertCommandToExecutable (Just (Command command))
  | Vector.null command = throwE NoCommand
  | otherwise = do
    let executableName = Vector.head command
    executablePath <- parseAbsOrRelFile executableName
    let commandArgs = Vector.tail command
    return $ ExecutableProgram executablePath (Args commandArgs)

readFixture ::
     FixtureType a => Path Abs Dir -> Fixture a -> Planning (Filtered a)
readFixture _ (Fixture (Inline contents) maybeFilter) =
  return $ includeFilter maybeFilter contents
readFixture location (Fixture (FileLocation path) maybeFilter) =
  includeFilter maybeFilter . deserializeFixture <$>
  withExceptT
    (handleMissingFileError path)
    (ExceptT $ tryIOError $ readFromPath (location </> path))

readFixtures ::
     FixtureType a
  => Path Abs Dir
  -> Fixtures a
  -> Planning (Vector (Filtered a))
readFixtures location (Fixtures fixtures) = mapM (readFixture location) fixtures

includeFilter :: Maybe FixtureFilter -> a -> Filtered a
includeFilter maybeFilter contents =
  maybe (Unfiltered contents) (Filtered contents) maybeFilter

handleMissingFileError :: Path Rel File -> IOError -> SmokePlanningError
handleMissingFileError path e =
  if isDoesNotExistError e
    then NonExistentFixture path
    else CouldNotReadFixture path e
