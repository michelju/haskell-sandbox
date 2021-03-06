module MutContainers.PriorityQueue (
    ExtractMinM(..),
    InsertValM(..),
)
where
import Containers.Prelude
import MutContainers.Map
import MutState.State

class ExtractMinM q where
    extractMinM :: (MutMonad s m, a ~ ValOf q, Ord a) => Mut s q -> m a 
class InsertValM q where
    insertValM :: (MutMonad s m, a ~ ValOf q, Ord a) => Mut s q -> a -> m ()
