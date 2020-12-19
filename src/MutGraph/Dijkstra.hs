module MutGraph.Dijkstra (
    Dijkstra, dijkstra,
    DijkstraSimpleM, dijkstraSimpleM,
    DijkstraM, dijkstraM,
    DijkstraInitM, dijkstraInitM,
    DijkstraLoopM, dijkstraLoopM,
    DijkstraScanM, dijkstraScanM,
) where
import Prelude 
import MutGraph.Graph
import MutState.State
---
import Control.Monad hiding (replicateM)
import MutContainers.PriorityQueue
import MutContainers.Container
---
import Control.Monad.ST
import MutContainers.List
import MutContainers.Vector
import MutContainers.Unbox
import MutContainers.Container
import MutContainers.Run
import MutContainers.Curry
import MutContainers.Heap
import MutContainers.Map
import MutContainers.Size

class Dijkstra g where
    dijkstra :: (GraphReqs g k h e l z, Num e, Ord e) =>
        g -> k -> l e

class DijkstraSimpleM g where
    dijkstraSimpleM :: (MutMonad s m, GraphReqs g k h e l z, Num e, Ord e) =>
        Cst s g -> k -> m (l e)

class DijkstraM g q scanned labels where
    dijkstraM :: (MutMonad s m, GraphReqs g k h e l z, Num e, Ord e,
        ValOf q ~ (e, k),
        KeyOf labels ~ k, ValOf labels ~ e, 
        KeyOf scanned ~ k, ValOf scanned ~ Bool) =>
        Mut s scanned -> Mut s labels -> Mut s q ->
        Cst s g -> k -> m ()

class DijkstraInitM g q scanned labels where
    dijkstraInitM :: (MutMonad s m, GraphReqs g k h e l z, Num e, Ord e,
        ValOf q ~ (e, k),
        KeyOf labels ~ k, ValOf labels ~ e, 
        KeyOf scanned ~ k, ValOf scanned ~ Bool) =>
        Mut s scanned -> Mut s labels -> Mut s q ->
        Cst s g -> k -> m ()

class DijkstraLoopM g q scanned labels where
    dijkstraLoopM :: (MutMonad s m, GraphReqs g k h e l z, Num e, Ord e,
        ValOf q ~ (e, k),
        KeyOf labels ~ k, ValOf labels ~ e, 
        KeyOf scanned ~ k, ValOf scanned ~ Bool) =>
        Mut s scanned -> Mut s labels -> Mut s q ->
        Cst s g -> m ()

class DijkstraScanM g q labels where
    dijkstraScanM :: (MutMonad s m, GraphReqs g k h e l z, Num e, Ord e,
        ValOf q ~ (e, k),
        KeyOf labels ~ k, ValOf labels ~ e) =>
        Mut s labels -> Mut s q -> Cst s g -> k -> e -> m ()


instance (
    GraphReqs g k h e l z,
    DijkstraInitM g q scanned labels,
    DijkstraLoopM g q scanned labels
    ) => DijkstraM g q scanned labels where
    dijkstraM scanned labels queue graph source = do
        dijkstraInitM scanned labels queue graph source
        dijkstraLoopM scanned labels queue graph
    {-# INLINE dijkstraM #-}

instance (
    GraphReqs g k h e l z,
    WriteM scanned,
    WriteM labels,
    Bounded e,
    EmptyM q,
    Ord k,
    InsertValM q,
    Traversable l,
    ListGraphNodesC g
    ) => DijkstraInitM g q scanned labels where
    dijkstraInitM scanned labels queue graph source = do
        let infinity = maxBound
        listGraphNodesC graph >>=
            mapM_ (\k -> do
                writeM labels k infinity
                writeM scanned k False)
        writeM labels source 0
        emptyM queue
        insertValM queue (0, source)
    {-# INLINE dijkstraInitM #-}

instance (
    GraphReqs g k h e l z,
    ReadC scanned,
    WriteM scanned, MutToCst scanned,
    DijkstraScanM g q labels,
    ExtractMinM q,
    Ord k,
    IsEmptyC q,
    MutToCst q
    ) => DijkstraLoopM g q scanned labels where
    dijkstraLoopM scanned labels queue graph = loop where
        loop = do
            empty <- isEmptyC (cst queue)
            unless empty $ do
                (du, u) <- extractMinM queue
                wasScanned <- readC (cst scanned) u
                unless wasScanned $ do
                    dijkstraScanM labels queue graph u du 
                    writeM scanned u True
                loop
    {-# INLINE dijkstraLoopM #-}

instance (
    GraphReqs g k h e l z,
    Ord k,
    InsertValM q,
    Traversable l,
    ReadC labels,
    MutToCst labels,
    WriteM labels,
    ListGraphEdgesFromC g
    ) => DijkstraScanM g q labels where
    dijkstraScanM labels queue graph u du = 
        listGraphEdgesFromC graph u >>=
        mapM_ (\edge -> do
            let v = getEdgeHead edge
            let luv = getEdgeData edge
            dv <- readC (cst labels) v
            let dnew = du + luv
            when (dv > dnew) $ do
                writeM labels v dnew
                insertValM queue (dnew, v))
    {-# INLINE dijkstraScanM #-}



type GenInputs g k h e l z = (g, k)
type GenOutputs l e = l e
type InputsM m s g k e labels scanned q = (
        Mut s scanned,
        Mut s labels,
        Mut s q,
        Cst s g,
        k
    )
type OutputsM m s g e labels = (Mut s labels, Cst s g)
type GenInputsM s m g k h e l z = (Cst s g, k)
type GenOutputsM s m l e = l e

instance (
    GraphReqs g k h e l z,
    UThawM g,
    DijkstraSimpleM g,
    MutToCst g
    ) => Dijkstra g where
    dijkstra _graph _source =
        runST $ runM formatInputsM runAlgoM formatOutputsM
            (_graph, _source)
        where
            formatInputsM :: (MutMonad s m) =>
                GenInputs g k h e l z -> m (GenInputsM s m g k h e l z)
            formatInputsM (graph, source) = do
                mgraph <- uthawM graph
                return (cst mgraph, source)
            runAlgoM :: (MutMonad s m) =>
                GenInputsM s m g k h e l z -> m (GenOutputsM s m l e)
            runAlgoM = uncurryN dijkstraSimpleM
            formatOutputsM :: (MutMonad s m) =>
                GenOutputsM s m l e -> m (GenOutputs l e)
            formatOutputsM = return
    {-# INLINE dijkstra #-}

type Scanned = VectorU
type Labels = VectorU
type Queue e k = Heap (VectorU (e, k)) Int
type QueueVec = VectorU

instance (
    GraphReqs g k h e l z,
    GetGraphNodeCountC g,
    Num k,
    Unbox e,
    q ~ Queue e k,
    scanned ~ Scanned Bool,
    labels ~ Labels e,
    qvec ~ QueueVec (e, k),
    z ~ k,
    k ~ KeyOf labels,
    k ~ KeyOf scanned,
    k ~ SizeOf labels,
    k ~ SizeOf scanned,
    UFreezeC labels,
    ReplicateM labels,
    ReplicateM scanned,
    ReplicateM qvec,
    MakeHeapM qvec q z (e, k),
    DijkstraM g q scanned labels,
    Convert labels (l e),
    MutToCst labels
    ) => DijkstraSimpleM g where
    dijkstraSimpleM _graph _source =
        runM formatInputsM runAlgoM formatOutputsM 
            (_graph, _source)
        where
            formatInputsM :: (MutMonad s m) =>
                GenInputsM s m g k h e l z -> 
                m (InputsM m s g k e labels scanned q)
            formatInputsM (mgraph, source) = do
                n <- getGraphNodeCountC mgraph
                queue_vec :: Mut s qvec <- replicateM n $ return (0, 0)
                queue <- makeHeapM queue_vec (0 :: z)
                labels <- replicateM n $ return 0
                scanned <- replicateM n $ return False
                return (scanned, labels, queue, mgraph, source)
            runAlgoM :: (MutMonad s m) =>
                InputsM m s g k e labels scanned q ->
                m (OutputsM m s g e labels)
            runAlgoM inputs = do
                let (_, labels, _, mgraph, _) = inputs
                uncurryN dijkstraM inputs
                return (labels, mgraph)
            formatOutputsM :: (MutMonad s m) =>
                OutputsM m s g e labels -> m (GenOutputsM s m l e)
            formatOutputsM (labels, _) = ufreezeC (cst labels) >>= (return . convert)
    {-# INLINE dijkstraSimpleM #-}
