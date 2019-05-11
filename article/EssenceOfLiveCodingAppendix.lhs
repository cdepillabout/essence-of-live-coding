\documentclass{essence}

\begin{document}
\title{The essence of live coding: Change the program, keep the state!}
\subtitle{Appendix}

\begin{abstract}
This file supplies more detailed discussions,
such as the somewhat technical derivations of the \mintinline{haskell}{Applicative} and \mintinline{haskell}{Monad} type classes.
It is not necessary to read it in order to appreciate the main paper,
but some readers may want to satisfy their curiosity.
\end{abstract}

\maketitle

\section{Arrows and typeclasses}

The \mintinline{haskell}{Arrow} type class also allows for data-parallel composition:
\begin{spec}
(***)
  :: Monad m
  => Cell  m  a      b
  -> Cell  m     c      d
  -> Cell  m (a, c) (b, d)
\end{spec}
As for \mintinline{haskell}{(>>>)},
the state type of the composed cell is the product type of the constituent states.
In the resulting cell \mintinline{haskell}{cell1 *** cell2},
two inputs are received.
First, \mintinline{haskell}{cell1} is stepped with the input \mintinline{haskell}{a},
then \mintinline{haskell}{cell2} is stepped with \mintinline{haskell}{b}.

The parallel composition operator has a dual,
supplied by the \mintinline{haskell}{ArrowChoice} type class,
\fxwarning{Cite something? For example, we fulfil the noninterference (?) law from "Settable and Non-Interfering Signal Functions for FRP - How a First-Order Switch is More Than Enough"}
which \mintinline{haskell}{Cell}s implement:
\begin{spec}
(+++)
  :: Monad m
  => Cell m         a            b
  -> Cell m           c            d
  -> Cell m (Either a c) (Either b d)
\end{spec}
Like \mintinline{haskell}{cell1 *** cell2},
its dual \mintinline{haskell}{cell1 +++ cell2} holds the state of both cells.
But while the former executes both cells,
and consumes input and produces output for both of them,
the latter steps only one of them forward each time,
depending on which input was provided.
This enables basic control flow in arrow expressions,
such as \mintinline{haskell}{if}- and \mintinline{haskell}{case}-statements.
We can momentarily switch from one cell to another,
depending on live input.
For example, the following two cells are equal:
\begin{code}
cellLR = proc lr -> do
  case lr of
    Left  () -> returnA -< "Left!"
    Right () -> returnA -< "Right!"

cellLR'
  =   arr (const "Left!")
  +++ arr (const "Right!")
\end{code}

The \mintinline{haskell}{ArrowLoop} class exists to enable recursive definitions in arrow expressions,
and once again \mintinline{haskell}{Cell}s implement it:
\begin{spec}
loop
  :: MonadFix m
  => Cell     m (a, s) (b, s)
  -> Cell     m  a      b
\end{spec}
A word of caution has to be issued here:
The instance is implemented using the monadic fixed point operator \mintinline{haskell}{mfix} \cite{MonadFix},
and can thus crash at runtime if the current output of the intermediate value \mintinline{haskell}{s} is calculated strictly from the current input \mintinline{haskell}{s}.

We would like to have all basic primitives needed to develop standard synchronous signal processing components,
without touching the \mintinline{haskell}{Cell} constructor anymore.
One crucial bit is missing to achieve this goal:
Encapsulating state.
\fxerror{This is unclear. Either have to stress that it's maybe not so nice to encapsulate state by explicitly building the Cell, like we have done with the sum, or move feedback at the beginning of the section.}
The most general such construction is the feedback loop:
\begin{code}
feedback
  :: (Monad m, Data s)
  =>                s
  -> Cell   m   (a, s) (b, s)
  -> Cell   m    a      b
\end{code}
Let us have a look at its internal state:
\begin{spec}
data Feedback sPrevious sAdditional = Feedback
  { sPrevious   :: sPrevious
  , sAdditional :: sAdditional
  }
\end{spec}
In \mintinline{haskell}{feedback sAdditional cell},
the \mintinline{haskell}{cell} has state \mintinline{haskell}{sPrevious},
and to this state we add \mintinline{haskell}{sAdditional}.
The additional state is received by \mintinline{haskell}{cell} as explicit input,
and \mintinline{haskell}{feedback} hides it.

Note that \mintinline{haskell}{feedback} and \mintinline{haskell}{loop} are different.
While \mintinline{haskell}{loop} provides immediate recursion, it doesn't add new state.
\mintinline{haskell}{feedback} requires an initial state and delays it,
but in turn it is always safe to use since it does not use \mintinline{haskell}{mfix}.

\begin{comment}
\begin{code}
newtype Feedback s s' = Feedback (s, s')
  deriving Data

feedback s (Cell state step) = Cell { .. }
  where
    cellState = Feedback (state, s)
    cellStep (Feedback (state, s)) a = do
      ((b, s'), state') <- step state (a, s)
      return (b, Feedback (state', s'))
\end{code}
\end{comment}

\input{../src/LiveCoding/Coalgebra.lhs}
\fxerror{We've now switched to using runExceptC, so liveBind is implemented in terms of it.}
We would like to adopt this approach here,
but we are forewarned:
\mintinline{haskell}{Cell}s are slightly less expressive than Dunai's stream functions,
due to the \mintinline{haskell}{Data} constraint on the internal state.
\section{Monads for control flow}
\input{../src/LiveCoding/LiveBind.lhs}
\input{../src/LiveCoding/CellExcept/Applicative.lhs}
\input{../src/LiveCoding/CellExcept/Monad.lhs}

\bibliography{EssenceOfLiveCoding.bib}
\end{document}
