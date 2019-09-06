{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TupleSections #-}

-- base
import Control.Arrow
import Data.Functor.Identity
import System.IO.Unsafe (unsafePerformIO)

-- test-framework
import Test.Framework

-- test-framework-quickcheck2
import Test.Framework.Providers.QuickCheck2

-- QuickCheck
import Test.QuickCheck

-- essence-of-live-coding
import LiveCoding
import qualified TestData.Foo1 as Foo1
import qualified TestData.Foo2 as Foo2

intToInteger :: Int -> Integer
intToInteger = toInteger

main = defaultMain tests

tests =
  [ testGroup "Builtin types"
    [ testProperty "Same"
      $ \(x :: Integer) (y :: Integer) -> x === migrate y x
    , testProperty "Different"
      $ \(x :: Integer) (y :: Bool) -> y === migrate y x
    ]
  , testGroup "Product types"
    [ testProperty "Adds default field"
      $ Foo1.foo' === migrate Foo1.foo Foo2.foo
    , testProperty "Keeps only sensible field"
      $ Foo2.foo' === migrate Foo2.foo Foo1.foo
    ]
  , testGroup "Records"
    [ testProperty "Takes record field names into account"
      $ \barA barB barC barC2 barD
      -> Foo2.Bar { barC = barC2, .. } === migrate Foo2.Bar { barC = barC2, .. } Foo1.Bar { .. }
    , testProperty "Migrates nested records"
      $ Foo2.baz' === migrate Foo2.baz Foo1.baz
    ]
  , testGroup "Constructors"
    [ testProperty "Finds correct constructor"
      $ \x y z -> migrate (Foo2.Fooo z) (Foo1.Foo x y) === Foo2.Foo x
    , testProperty "Finds correct constructor with records"
      $ \barA barB barC baarA baarB -> migrate Foo2.Bar { .. } Foo1.Baar { .. } === Foo2.Baar { .. }
    ]
  , testGroup "User migration"
    [ testProperty "Can add migration from Int to Integer"
      $ Foo2.frob' === migrateWith (userMigration intToInteger) Foo2.frob Foo1.frob
    ]
  , testGroup "Newtypes"
    [ testProperty "Wraps into newtype"
      $ \(x :: Integer) -> Foo2.Frob x === migrate Foo2.frob x
    ]
  , testGroup "Debugging"
    [ testProperty "To debugging state"
      $ \(x :: Int) (y :: Int) (z :: Int)
      -> Debugging { dbgState = x, state = y } === migrate Debugging { dbgState = x, state = z } y
    , testProperty "From debugging state"
    $ \(x :: Int) (y :: Int) (z :: Int)
    -> x === migrate y Debugging { dbgState = z, state = x }
    ]
  , testGroup "Cells"
    [ testGroup "Sequential composition"
      [ testProperty "From 1" CellMigrationSimulation
          { cell1 = sumC >>> arr toInteger
          , cell2 = sumC >>> arr toInteger >>> sumC
          , input1 = [1, 1, 1] :: [Int]
          , input2 = [1, 1, 1]
          , output1 = [0, 1, 2]
          , output2 = [0, 3, 7]
          }
      ]
    , testGroup "Choice"
      [ testProperty "From left" CellMigrationSimulation
        { cell1 = arr fromEither >>> sumC >>> arr toInteger
        , cell2 = (sumC >>> arr toInteger) ||| (arr toInteger >>> sumC)
        , input1 = [Left  1, Right 1, Left  (1 :: Int)]
        , input2 = [Right 1, Left  1, Right 1]
        , output1 = [0, 1, 2]
        , output2 = [0, 3, 1]
        }
      ]
    , testGroup "Control flow"
      [ testProperty "Into safe" CellMigrationSimulation
        { cell1 = countFrom 0
        , cell2 = safely $ do
            try $ countFrom 10  >>> throwIf (>  1) ()
            safe $ countFrom 20
        , input1 = replicate 3 ()
        , input2 = replicate 3 ()
        , output1 = [0, 1, 2]
        , output2 = [23, 24, 25]
        }
      , testProperty "Into more exceptions" CellMigrationSimulation
        { cell1 = withEvilDebugger $ safely $ do
            try $ countFrom 0 >>> throwIf (> 1) ()
            safe $ countFrom 10
        , cell2 = withEvilDebugger $ safely $ do
            try $ countFrom 0  >>> throwIf (>  1) ()
            try $ countFrom 20 >>> throwIf (> 21) ()
            safe $ countFrom 30
        , input1 = replicate 3 ()
        , input2 = replicate 3 ()
        , output1 = [0, 1, 10]
        , output2 = [21, 30, 31]
        }
      ]
    ]
  ]

withEvilDebugger :: Cell IO a b -> Cell Identity a b
withEvilDebugger cell = hoistCell (Identity . unsafePerformIO) $ withDebuggerC cell statePrint

countFrom :: Monad m => Int -> Cell m () Int
countFrom n = arr (const 1) >>> sumC >>> arr (+ n)

fromEither (Left  a) = a
fromEither (Right a) = a

data CellMigrationSimulation a b = CellMigrationSimulation
  { cell1 :: Cell Identity a b
  , cell2 :: Cell Identity a b
  , input1 :: [a]
  , input2 :: [a]
  , output1 :: [b]
  , output2 :: [b]
  }

instance (Eq b, Show b) => Testable (CellMigrationSimulation a b) where
  property CellMigrationSimulation { .. }
    = let Identity (output1', output2') = simulateCellMigration cell1 cell2 input1 input2
      in output1 === output1' .&&. output2 === output2'

simulateCellMigration :: Monad m => Cell m a b -> Cell m a b -> [a] -> [a] -> m ([b], [b])
simulateCellMigration cell1 cell2 as1 as2 = do
  (bs1, cell1') <- steps cell1 as1
  let cell2' = hotCodeSwapCell cell2 cell1'
  (bs2, _) <- steps cell2' as2
  return (bs1, bs2)
