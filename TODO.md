`run` currently unwraps all the arguments passed in. However, it should really only unwrap arguments which
are related to the interface on which we are dispatching. 