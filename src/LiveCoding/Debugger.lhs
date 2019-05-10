\begin{comment}
\begin{code}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}

module LiveCoding.Debugger where

-- base
import Control.Concurrent
import Control.Monad (void)
import Data.Data
import Data.IORef

-- syb
import Data.Generics.Text

\end{code}
\end{comment}

\subsection{Debugging the live state}
Having the complete state of the program in one place allows us to inspect and debug it in a central place.
We might want to display the state, or aspects of it,
interact with the user and possibly even change it in place,
if necessary.
These patterns are abstracted in a simple definition:
\fxerror{Could make Debuggers Cells as well,
or rather \mintinline{haskell}{type Debugger = LiveProgram (ReaderT (Data s => s)) IO}.
Then have \mintinline{haskell}{withDebugger :: LiveProgram IO -> Debugger -> LiveProgram IO.
Either the dbugger coul dbe synhronous,
or even asynchronous and only rceive th estate through an IORef.}
\begin{code}
newtype Debugger = Debugger
  { debugState
      :: forall s . Data s => s -> IO s
  }
\end{code}
A simple debugger does not modify the state and prints it to the console:
\begin{code}
gshowDebugger = Debugger $ \state -> do
  putStrLn $ gshow state
  return state
\end{code}
Thanks to the \mintinline{haskell}{Data} typeclass,
the state does not need to be an instance of \mintinline{haskell}{Show} for this to work.
A more sophisticated debugger could connect to a GUI and display the state there,
even offering the user to edit it live.
\fxwarning{Should I explain countDebugger? What for?}

Debuggers are endomorphisms in the Kleisli category of \mintinline{haskell}{IO},
and thus \mintinline{haskell}{Monoid}s:
A pair of them can be chained by executing them sequentially,
and the trivial debugger purely \mintinline{haskell}{return}s the state unchanged.

We can start them alongside with the live program:
\fxwarning{Move appropriately, e.g. a separate file RuntimeDebugger}
\begin{spec}
launchWithDebugger
  :: LiveProgram IO
  -> Maybe Int
  -> Debugger
  -> IO (MVar (LiveProgram IO))
\end{spec}
\fxerror{Implement the Maybe Int parameter!}
The optional parameter of type \mintinline{haskell}{Maybe Int} specifies between how many execution steps the debugger should be called.
(For an audio application, calling it on every sample would be an unbearable performance penalty.)

\fxwarning{Automatise this and the next output}
Inspecting the state of the example \mintinline{haskell}{printSineWait} from Section \ref{sec:control flow context} is daunting, though:
\begin{verbatim}
Waiting...
(Composition ((,) (Composition ((,) (()) 
(Composition ((,) (()) (Composition ((,) 
(Composition ((,) (()) (Composition ((,) 
(Parallel ((,) (Composition ((,) (()) 
(NotThrown (Composition ((,) (()) 
[...]
\end{verbatim}
\fxerror{I still hav the tuples here!}
The arrow syntax desugaring introduces a lot of irrelevant overhead such as compositions with the trivial state type \mintinline{haskell}{()},
hiding the actual parts of the state we are interested in.
Luckily, it is a simple, albeit lengthy exercise in generic programming to prune all irrelevant parts of the state,
resulting in a tidy output\footnote{%
Line breaks were added to fit the columns.}
like:
\begin{verbatim}
Waiting...
NotThrown: (1.0e-3)
 >>> +(0.0) >>> (0.0)+
 >>> (1)
NotThrown: (2.0e-3)
 >>> +(0.0) >>> (0.0)+
 >>> (2)
[...]
Waiting...
NotThrown: (2.0009999999998906)
 >>> +(0.0) >>> (0.0)+
 >>> (2001)
Exception:
 >>> +(3.9478417604357436e-3) >>> (0.0)+
 >>> (2002)
[...]
\end{verbatim}
\begin{comment}
Exception:
 >>> +(7.895683520871487e-3) >>>
 (3.947841760435744e-6)+
 >>> (2003)
\end{comment}
First, the cell is initialised in a state where the exception hasn't been thrown yet,
and the local time has progressed to \mintinline{haskell}{1.0e-3} seconds.
The next line corresponds to the initial state (position and velocity) of the sine generator which will be activated after the exception has been thrown,
followed by the internal counter of \mintinline{haskell}{printEverySecond}.
In the next step, local time and counter have progressed.
Two thousand steps later, the exception is finally thrown,
and the sine generator springs into action.

\begin{comment}
\begin{code}
instance Semigroup Debugger where
  debugger1 <> debugger2 = Debugger $ \s -> debugState debugger1 s >>= debugState debugger2

instance Monoid Debugger where
  mempty = noDebugger

noDebugger :: Debugger
noDebugger = Debugger $ return

newtype CountObserver = CountObserver { observe :: IO Integer }

countDebugger :: IO (Debugger, CountObserver)
countDebugger = do
  countRef <- newIORef 0
  observeVar <- newEmptyMVar
  let debugger = Debugger $ \s -> do
        n <- readIORef countRef
        putMVar observeVar n
        yield
        void $ takeMVar observeVar
        writeIORef countRef $ n + 1
        return s
      observer = CountObserver $ yield >> readMVar observeVar
  return (debugger, observer)

await :: CountObserver -> Integer -> IO ()
await CountObserver { .. } nMax = go
 where
  go = do
    n <- observe
    if n > nMax then return () else go
\end{code}
\end{comment}
\fxerror{Examples for cells and stateprintdebugger}
