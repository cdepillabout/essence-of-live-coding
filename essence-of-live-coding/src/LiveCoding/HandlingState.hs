{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RecordWildCards #-}

{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module LiveCoding.HandlingState where

-- base
import Control.Arrow (returnA, arr, (>>>))
import Data.Data

-- transformers
import Control.Monad.Trans.Class (MonadTrans(lift))
import Control.Monad.Trans.State.Strict
import Data.Foldable (traverse_)
import Data.Functor (($>))

-- containers
import Data.IntMap
import qualified Data.IntMap as IntMap
import qualified Data.IntSet as IntSet
import qualified Data.List as List

-- mmorph
import Control.Monad.Morph

-- fused-effects
import Control.Algebra

-- essence-of-live-coding
import LiveCoding.Cell
import LiveCoding.Cell.Monad
import LiveCoding.Cell.Monad.Trans
import LiveCoding.LiveProgram
import LiveCoding.LiveProgram.Monad.Trans

data Handling h where
  Handling
    :: { key    :: Key
       , handle :: h
       }
    -> Handling h
  Uninitialized :: Handling h

data HandlingStateE m a where
  Register :: m () -> HandlingStateE m Key
  -- TODO maybe HandlingStateT m () -> HandlingStateE m Key?
  Reregister :: m () -> Key -> HandlingStateE m ()
  UnregisterAll :: HandlingStateE m ()
  DestroyUnregistered :: HandlingStateE m ()

instance MFunctor HandlingStateE where
  hoist morphism (Register action) = Register $ morphism action
  hoist morphism (Reregister action key) = Reregister (morphism action) key
  hoist morphism UnregisterAll = UnregisterAll
  hoist morphism DestroyUnregistered = DestroyUnregistered

instance Algebra sig m => Algebra (HandlingStateE :+: sig) (HandlingStateT m) where
  alg handler (L (Register destructor)) ctx = do
    HandlingState { .. } <- HandlingStateT get
    let key = nHandles + 1
    let thing = unHandlingStateT $ handler $ destructor <$ ctx
    HandlingStateT $ put HandlingState
      { nHandles = key
      , destructors = insertDestructor _ key destructors
      }
      -- type Handler ctx m n = forall x . ctx (m x) -> n (ctx x)

    return $ key <$ ctx
  alg handler (L (Reregister action key)) ctx = HandlingStateT $ do
    HandlingState { .. } <- get
    put HandlingState { destructors = insertDestructor (_ action) key destructors, .. }
    return ctx
  alg handler (L UnregisterAll) ctx = ctx <$ unregisterAll
  alg handler (L DestroyUnregistered) ctx = ctx <$ destroyUnregistered
  alg handler (R sig) ctx = HandlingStateT $ alg (unHandlingStateT . handler) (R sig) ctx

-- | In this monad, handles can be registered,
--   and their destructors automatically executed.
--   It is basically a monad in which handles are automatically garbage collected.
newtype HandlingStateT m a = HandlingStateT
  { unHandlingStateT :: StateT (HandlingState m) m a }
  deriving (Functor, Applicative, Monad)

type Destructors m = IntMap (Destructor m)

-- | Hold a map of registered handle keys and destructors
data HandlingState m = HandlingState
  { nHandles    :: Key
  , destructors :: Destructors m
  }
  deriving Data

initHandlingState :: HandlingState m
initHandlingState = HandlingState
  { nHandles = 0
  , destructors = IntMap.empty
  }

-- | Handle the 'HandlingStateT' effect _without_ garbage collection.
--   Apply this to your main loop after calling 'foreground'.
--   Since there is no garbage collection, don't use this function for live coding.
runHandlingStateT
  :: Monad m
  => HandlingStateT m a
  -> m a
runHandlingStateT = flip evalStateT initHandlingState . unHandlingStateT

{- | Apply this to your main live cell before passing it to the runtime.

On the first tick, it initialises the 'HandlingState' at "no handles".

On every step, it does:

1. Unregister all handles
2. Register currently present handles
3. Destroy all still unregistered handles
   (i.e. those that were removed in the last tick)
-}
runHandlingStateC
  :: forall m a b .
     (Monad m, Typeable m)
  => Cell (HandlingStateT m) a b
  -> Cell                 m  a b
runHandlingStateC cell = flip runStateC_ initHandlingState
  $ hoistCellOutput (unHandlingStateT . garbageCollected) cell

-- | Like 'runHandlingStateC', but for whole live programs.
runHandlingState
  :: (Monad m, Typeable m)
  => LiveProgram (HandlingStateT m)
  -> LiveProgram                 m
runHandlingState LiveProgram { .. } = flip runStateL initHandlingState LiveProgram
  { liveStep = unHandlingStateT . garbageCollected . liveStep
  , ..
  }

garbageCollected
  :: Monad m
  => HandlingStateT m a
  -> HandlingStateT m a
garbageCollected action = unregisterAll >> action <* destroyUnregistered

data Destructor m = Destructor
  { isRegistered :: Bool
  , action       :: m ()
  }


register
  :: (Monad m, Algebra sig m)
  => m () -- ^ Destructor
  -> HandlingStateT m Key
register destructor = do
  HandlingState { .. } <- get
  let key = nHandles + 1
  put HandlingState
    { nHandles = key
    , destructors = insertDestructor destructor key destructors
    }
  return key

reregister
  :: Monad m
  => m ()
  -> Key
  -> HandlingStateT m ()
reregister action key = do
  HandlingState { .. } <- get
  put HandlingState { destructors = insertDestructor action key destructors, .. }

insertDestructor
  :: m ()
  -> Key
  -> Destructors m
  -> Destructors m
insertDestructor action key destructors =
  let destructor = Destructor { isRegistered = True, .. }
  in  insert key destructor destructors

unregisterAll
  :: Monad m
  => HandlingStateT m ()
unregisterAll = do
  HandlingState { .. } <- get
  let newDestructors = IntMap.map (\destructor -> destructor { isRegistered = False }) destructors
  put HandlingState { destructors = newDestructors, .. }

destroyUnregistered
  :: Monad m
  => HandlingStateT m ()
destroyUnregistered = do
  HandlingState { .. } <- get
  let
      (registered, unregistered) = partition isRegistered destructors
  traverse_ (lift . action) unregistered
  put HandlingState { destructors = registered, .. }

-- * 'Data' instances

dataTypeHandling :: DataType
dataTypeHandling = mkDataType "Handling" [handlingConstr, uninitializedConstr]

handlingConstr :: Constr
handlingConstr = mkConstr dataTypeHandling "Handling" [] Prefix

uninitializedConstr :: Constr
uninitializedConstr = mkConstr dataTypeHandling "Uninitialized" [] Prefix

instance (Typeable h) => Data (Handling h) where
  dataTypeOf _ = dataTypeHandling
  toConstr Handling { .. } = handlingConstr
  toConstr Uninitialized = uninitializedConstr
  gunfold _cons nil constructor = nil Uninitialized

dataTypeDestructor :: DataType
dataTypeDestructor = mkDataType "Destructor" [ destructorConstr ]

destructorConstr :: Constr
destructorConstr = mkConstr dataTypeDestructor "Destructor" [] Prefix

instance Typeable m => Data (Destructor m) where
  dataTypeOf _ = dataTypeDestructor
  toConstr Destructor { .. } = destructorConstr
  gunfold _ _ = error "Destructor.gunfold"
