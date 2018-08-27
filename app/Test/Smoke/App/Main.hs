{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (displayException)
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ask, runReaderT)
import Data.Monoid ((<>))
import Data.String (fromString)
import qualified Data.Text as Text
import System.Exit
import Test.Smoke
import Test.Smoke.App.Diff
import Test.Smoke.App.OptionTypes
import Test.Smoke.App.Options
import Test.Smoke.App.Print
import Text.Printf (printf)

main :: IO ()
main = do
  options <- parseOptions
  tests <- discoverTests (optionsExecution options)
  results <- runTests tests
  case optionsMode options of
    Check -> outputResults options results
    Bless -> outputResults options =<< blessResults results

outputResults :: AppOptions -> TestResults -> IO ()
outputResults options results = do
  runReaderT
    (do printResults results
        printSummary results)
    options
  exitAccordingTo results

printResults :: TestResults -> Output ()
printResults = mapM_ printResult

printResult :: TestResult -> Output ()
printResult (TestSuccess name) = do
  printTitle name
  putGreenLn "  succeeded"
printResult (TestFailure name (TestExecutionPlan _ test _ _ stdIn) statusResult stdOutResult stdErrResult) = do
  printTitle name
  printFailingInput "args" (Text.unlines . map fromString <$> testArgs test)
  printFailingInput "input" (unStdIn <$> stdIn)
  printFailingOutput "status" (int . unStatus <$> statusResult)
  printFailingOutput "output" (unStdOut <$> stdOutResult)
  printFailingOutput "error" (unStdErr <$> stdErrResult)
printResult (TestError name NoCommand) = do
  printTitle name
  printError "There is no command."
printResult (TestError name NoInput) = do
  printTitle name
  printError "There are no args or STDIN."
printResult (TestError name NoOutput) = do
  printTitle name
  printError "There are no STDOUT or STDERR."
printResult (TestError name (NonExistentCommand executableName)) = do
  printTitle name
  printError $
    "The application \"" <> Text.pack executableName <> "\" does not exist."
printResult (TestError name (NonExecutableCommand executableName)) = do
  printTitle name
  printError $
    "The application \"" <> Text.pack executableName <> "\" is not executable."
printResult (TestError name (CouldNotExecuteCommand executableName e)) = do
  printTitle name
  printError $
    "The application \"" <> Text.pack executableName <>
    "\" could not be executed.\n" <>
    fromString e
printResult (TestError name (CouldNotWriteFixture fixtureName fixtureValue)) = do
  printTitle name
  printError $
    "Could not write the fixture \"" <> Text.pack fixtureName <> "\":\n" <>
    fixtureValue
printResult (TestError name (BlessingFailed e)) = do
  printTitle name
  printError $ "Blessing failed.\n" <> fromString (displayException e)
printResult (TestError name (CouldNotBlessAMissingValue propertyName)) = do
  printTitle name
  printError $
    "There are no expected \"" <> Text.pack propertyName <>
    "\" values, so the result cannot be blessed.\n"
printResult (TestError name (CouldNotBlessWithMultipleValues propertyName)) = do
  printTitle name
  printError $
    "There are multiple expected \"" <> Text.pack propertyName <>
    "\" values, so the result cannot be blessed.\n"

printTitle :: String -> Output ()
printTitle = liftIO . putStrLn

printFailingInput :: Foldable f => String -> f Contents -> Output ()
printFailingInput name value =
  forM_ value $ \v -> do
    putRed $ fromString $ indentedKey ("  " ++ name ++ ":")
    putPlainLn $ indented outputIndentation v

printFailingOutput :: String -> PartResult Contents -> Output ()
printFailingOutput _ PartSuccess = return ()
printFailingOutput name (PartFailure expected actual) = do
  putRed $ fromString $ indentedKey ("  " ++ name ++ ":")
  printDiff (head expected) actual
  forM_ (tail expected) $ \e -> do
    putRed "      or: "
    printDiff e actual

printSummary :: TestResults -> Output ()
printSummary results = do
  putEmptyLn
  let testCount = length results
  let failureCount = length failures
  case failureCount of
    0 -> putGreenLn (int testCount <> " tests, 0 failures")
    1 -> putRedLn (int testCount <> " tests, 1 failure")
    n -> putRedLn (int testCount <> " tests, " <> int n <> " failures")
  where
    failures = filter isFailure results

printError :: Contents -> Output ()
printError = putRedLn . indentedAll messageIndentation

outputIndentation :: Int
outputIndentation = 10

messageIndentation :: Int
messageIndentation = 2

indentedKey :: String -> String
indentedKey = printf ("%-" ++ show outputIndentation ++ "s")

printDiff :: Contents -> Contents -> Output ()
printDiff left right = do
  AppOptions { optionsColor = color
             , optionsDiffEngine = DiffEngine {engineRender = renderDiff}
             } <- ask
  diff <- liftIO $ renderDiff color left right
  putPlainLn $ indented outputIndentation diff

exitAccordingTo :: TestResults -> IO ()
exitAccordingTo results =
  if failureCount == 0
    then exitSuccess
    else exitWith (ExitFailure 1)
  where
    failureCount = length (filter isFailure results)

isFailure :: TestResult -> Bool
isFailure TestSuccess {} = False
isFailure TestFailure {} = True
isFailure TestError {} = True
