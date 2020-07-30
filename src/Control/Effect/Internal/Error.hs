{-# OPTIONS_HADDOCK not-home #-}
{-# LANGUAGE DerivingVia #-}
module Control.Effect.Internal.Error where

import Data.Coerce

import Control.Applicative
import Control.Monad

import Control.Effect
import Control.Effect.Union
import Control.Effect.Type.Throw
import Control.Effect.Type.Catch
import Control.Effect.Type.Optional

import Control.Effect.Carrier

import Control.Monad.Trans.Except

newtype ThrowC e m a = ThrowC { unThrowC :: ExceptT e m a }
  deriving ( Functor, Applicative, Monad
           , Alternative, MonadPlus
           , MonadFix, MonadFail, MonadIO
           , MonadThrow, MonadCatch, MonadMask
           , MonadBase b, MonadBaseControl b
           )
  deriving (MonadTrans, MonadTransControl)

newtype ErrorC e m a = ErrorC { unErrorC :: ExceptT e m a }
  deriving ( Functor, Applicative, Monad
           , Alternative, MonadPlus
           , MonadFix, MonadFail, MonadIO
           , MonadThrow, MonadCatch, MonadMask
           , MonadBase b, MonadBaseControl b
           )
  deriving (MonadTrans, MonadTransControl)

instance ( Carrier m
         , Threads (ExceptT e) (Prims m)
         )
      => Carrier (ThrowC e m) where
  type Derivs (ThrowC e m) = Throw e ': Derivs m
  type Prims  (ThrowC e m) = Prims m

  algPrims = coerce (thread @(ExceptT e) (algPrims @m))
  {-# INLINE algPrims #-}

  reformulate n alg = powerAlg (reformulate (n . lift) alg) $ \case
    Throw e -> n (ThrowC (throwE e))
  {-# INLINE reformulate #-}


instance ( Carrier m
         , Threads (ExceptT e) (Prims m)
         )
      => Carrier (ErrorC e m) where
  type Derivs (ErrorC e m) = Catch e ': Throw e ': Derivs m
  type Prims  (ErrorC e m) = Optional ((->) e) ': Prims m

  algPrims = powerAlg (coerce (algPrims @(ThrowC e m))) $ \case
    Optional h m -> ErrorC (unErrorC m `catchE` (return . h))
  {-# INLINE algPrims #-}

  reformulate n alg =
    powerAlg (
      coerceReform (reformulate @(ThrowC e m)) n (weakenAlg alg)
    ) $ \case
      Catch m h -> join $ (alg . inj) $ Optional h (fmap pure m)
  {-# INLINE reformulate #-}


class    ( forall e. Threads (ExceptT e) p
         ) => ErrorThreads p
instance ( forall e. Threads (ExceptT e) p
         ) => ErrorThreads p