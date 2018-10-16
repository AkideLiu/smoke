{-# LANGUAGE ScopedTypeVariables #-}

module Test.Smoke.Bless
  ( blessResults
  ) where

import Control.Exception (catch, throwIO)
import Control.Monad (forM)
import qualified Data.Text.IO as TextIO
import qualified Data.Vector as Vector
import Test.Smoke.Types

blessResults :: Results -> IO Results
blessResults results =
  forM results $ \(SuiteResult suiteName testResults) -> do
    blessedResults <- forM testResults blessResult
    return $ SuiteResult suiteName blessedResults

blessResult :: TestResult -> IO TestResult
blessResult (TestResult test (TestFailure _ status stdOut stdErr))
  | isFailureWithMultipleExpectedValues stdOut =
    return $
    TestResult test $
    TestError (BlessError (CouldNotBlessWithMultipleValues "stdout"))
  | isFailureWithMultipleExpectedValues stdErr =
    return $
    TestResult test $
    TestError (BlessError (CouldNotBlessWithMultipleValues "stderr"))
  | otherwise =
    do case status of
         PartFailure _ actual -> writeFixture (testStatus test) actual
         _ -> return ()
       case stdOut of
         PartFailure _ actual -> writeFixtures (testStdOut test) actual
         _ -> return ()
       case stdErr of
         PartFailure _ actual -> writeFixtures (testStdErr test) actual
         _ -> return ()
       return $ TestResult test TestSuccess
     `catch` (\(e :: TestBlessErrorMessage) ->
                return (TestResult test $ TestError $ BlessError e)) `catch`
    (return . TestResult test . TestError . BlessIOException)
  where
    isFailureWithMultipleExpectedValues (PartFailure expected _) =
      Vector.length expected > 1
    isFailureWithMultipleExpectedValues _ = False
blessResult result = return result

writeFixture :: FixtureContents a => Fixture a -> a -> IO ()
writeFixture (InlineFixture contents) _ =
  throwIO $
  CouldNotWriteFixture (fixtureName contents) (serializeFixture contents)
writeFixture (FileFixture path) value =
  TextIO.writeFile path (serializeFixture value)

writeFixtures ::
     forall a. FixtureContents a
  => Fixtures a
  -> a
  -> IO ()
writeFixtures (Fixtures fixtures) value
  | Vector.length fixtures == 1 = writeFixture (Vector.head fixtures) value
  | otherwise =
    throwIO $ CouldNotBlessWithMultipleValues (fixtureName (undefined :: a))
