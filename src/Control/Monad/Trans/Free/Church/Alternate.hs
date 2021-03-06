module Control.Monad.Trans.Free.Church.Alternate where

import Control.Applicative
import Control.Monad.Trans
import Control.Monad.Base
import qualified Control.Monad.Fail as Fail
import Control.Effect.Internal.Union
import Control.Effect.Type.Unravel
import Control.Effect.Type.ListenPrim
import Control.Effect.Type.ReaderPrim
import Control.Effect.Type.Regional
import Control.Effect.Type.Optional
import Control.Monad.Catch hiding (handle)

newtype FreeT f m a = FreeT {
    unFreeT :: forall r
             . (forall x. m x -> (x -> r) -> r)
            -> (forall x. f x -> (x -> r) -> r)
            -> (a -> r) -> r
  }

class    (forall f. Threads (FreeT f) p) => FreeThreads p
instance (forall f. Threads (FreeT f) p) => FreeThreads p

liftF :: f a -> FreeT f m a
liftF f = FreeT $ \_ handler c -> f `handler` c
{-# INLINE liftF #-}

foldFreeT :: Monad m
          => (a -> b)
          -> (forall x. (x -> m b) -> f x -> m b)
          -> FreeT f m a
          -> m b
foldFreeT b c free = unFreeT free (>>=) (flip c) (pure . b)
{-# INLINE foldFreeT #-}

instance Functor (FreeT f m) where
  fmap f cnt = FreeT $ \bind handler c ->
    unFreeT cnt bind handler (c . f)
  {-# INLINE fmap #-}

instance Applicative (FreeT f m) where
  pure a = FreeT $ \_ _ c -> c a
  {-# INLINE pure #-}

  ff <*> fa = FreeT $ \bind handler c ->
    unFreeT ff bind handler $ \f ->
    unFreeT fa bind handler (c . f)
  {-# INLINE (<*>) #-}

  liftA2 f fa fb = FreeT $ \bind handler c ->
    unFreeT fa bind handler $ \a ->
    unFreeT fb bind handler (c . f a)
  {-# INLINE liftA2 #-}

  fa *> fb = fa >>= \_ -> fb
  {-# INLINE (*>) #-}

instance Monad (FreeT f m) where
  m >>= f = FreeT $ \bind handler c ->
    unFreeT m bind handler $ \a ->
    unFreeT (f a) bind handler c
  {-# INLINE (>>=) #-}

instance MonadBase b m => MonadBase b (FreeT f m) where
  liftBase = lift . liftBase
  {-# INLINE liftBase #-}

instance Fail.MonadFail m => Fail.MonadFail (FreeT f m) where
  fail = lift . Fail.fail
  {-# INLINE fail #-}

instance MonadTrans (FreeT f) where
  lift m = FreeT $ \bind _ c -> m `bind` c
  {-# INLINE lift #-}

instance MonadIO m => MonadIO (FreeT f m) where
  liftIO = lift . liftIO
  {-# INLINE liftIO #-}

instance MonadThrow m => MonadThrow (FreeT f m) where
  throwM = lift . throwM
  {-# INLINE throwM #-}

instance MonadCatch m => MonadCatch (FreeT f m) where
  catch main handle = FreeT $ \bind handler c ->
    unFreeT main
            (\m cn ->
               (`bind` id) $
                fmap cn m
                  `catch`
                \e -> pure $ unFreeT (handle e) bind handler c
            )
            handler
            c
  {-# INLINE catch #-}

instance Monoid w => ThreadsEff (FreeT f) (ListenPrim w) where
  threadEff = threadListenPrim $ \alg main -> FreeT $ \bind handler c ->
    unFreeT main
            (\m cn acc ->
               alg (ListenPrimListen m) `bind` \(s, a) ->
                  cn a $! acc <> s
            )
            (\eff cn acc -> handler eff (`cn` acc))
            (\a acc -> c (acc, a))
            mempty
  {-# INLINE threadEff #-}

instance ThreadsEff (FreeT f) (Regional s) where
  threadEff alg (Regionally s m) = FreeT $ \bind handler c ->
    unFreeT m (bind . alg . Regionally s) handler c
  {-# INLINE threadEff #-}

instance Functor s => ThreadsEff (FreeT f) (Optional s) where
  threadEff alg (Optionally sa main) = FreeT $ \bind handler c ->
    unFreeT main
            (\m cn ->
               (`bind` id) $ alg $ Optionally (fmap c sa) (fmap cn m)
            )
            handler
            c
  {-# INLINE threadEff #-}

instance ThreadsEff (FreeT f) (Unravel p) where
  threadEff alg (Unravel p cataM main) =
    unFreeT main
            (\m cn ->
               lift $ alg $ Unravel p
                                    (cataM . lift)
                                    (fmap (cataM . cn) m)
            )
            (\f c -> liftF f >>= c)
            return
  {-# INLINE threadEff #-}

instance ThreadsEff (FreeT f) (ReaderPrim i) where
  threadEff = threadReaderPrimViaRegional
  {-# INLINE threadEff #-}
