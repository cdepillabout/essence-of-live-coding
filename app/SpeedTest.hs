-- | For a simple speedtest, run e.g. the following command in Linux:
--   stack build && time stack exec SpeedTest

{-# LANGUAGE Arrows #-}

-- base
import Control.Arrow
import Control.Monad (void)
import Data.Data
import Data.Semigroup

-- transformers
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (runExceptT)

-- essenceoflivecoding
import LiveCoding.Bind
import LiveCoding.Exceptions
import LiveCoding.Cell
import LiveCoding.RuntimeIO

accum :: (Monad m, Semigroup w, Data w) => w -> Cell m w w
accum w0 = feedback w0 $ arr $ \(w, state) -> (state, w <> state)

mainCell = proc _ -> do
  x <- sine 1 -< ()
  s <- sumC   -< x
  m <- accum (Max 0) -< Max x
  m' <- accum (Min 0) -< Min x
  c <- sumC   -< (1 :: Int)
  if c > 1000 * 1000 * 10
    then do
      arrM (lift . print) -< (s, getMax m, getMin m')
      throwC  -< ()
    else returnA -< ()

main :: IO ()
main = void $ runExceptT $ foreground $ liveCell $ runCellExcept $ try mainCell
