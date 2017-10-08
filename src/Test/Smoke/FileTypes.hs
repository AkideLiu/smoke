module Test.Smoke.FileTypes
  ( FileType(..)
  , directoryGlob
  , directoryGlobs
  , fileGlob
  , fileGlobs
  ) where

import qualified System.FilePath.Glob as Glob

data FileType
  = Command
  | Args
  | StdIn
  | StdOut
  | StdErr
  | Status
  deriving (Eq, Show)

allFileTypes :: [FileType]
allFileTypes = [Command, Args, StdIn, StdOut, StdErr, Status]

directoryGlob :: FileType -> Glob.Pattern
directoryGlob Command = Glob.compile "*.command"
directoryGlob Args = Glob.compile "*.args"
directoryGlob StdIn = Glob.compile "*.in"
directoryGlob StdOut = Glob.compile "*.out*"
directoryGlob StdErr = Glob.compile "*.err*"
directoryGlob Status = Glob.compile "*.status"

directoryGlobs :: [(FileType, Glob.Pattern)]
directoryGlobs = zip allFileTypes $ map directoryGlob allFileTypes

fileGlob :: FilePath -> FileType -> Glob.Pattern
fileGlob path Command = Glob.compile (path ++ ".command")
fileGlob path Args = Glob.compile (path ++ ".args")
fileGlob path StdIn = Glob.compile (path ++ ".in")
fileGlob path StdOut = Glob.compile (path ++ ".out*")
fileGlob path StdErr = Glob.compile (path ++ ".err*")
fileGlob path Status = Glob.compile (path ++ ".status")

fileGlobs :: FilePath -> [(FileType, Glob.Pattern)]
fileGlobs path = zip allFileTypes $ map (fileGlob path) allFileTypes
