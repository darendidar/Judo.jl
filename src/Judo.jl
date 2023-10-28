module Judo
using Random
export 
    # variables.jl
    Variable, Parameter, Literal, 
    
    # functions.jl
    broadcastto, sumto, mean_squared_error,
    affine, sigmoid, gradient!, ⋅,
    relu, softmax, softmax_cross_entropy,
    @inference, @createfunc, 

    # layers.jl
    Linear, Layer, @createmodel, MLP,

    # optimizer.jl
    @createopt, setup!, update!, SGD,
    MomentumSGD, 

    # utils.jl
    cleargrad!, cleargrads!, plot_dot_graph,
    params,

    # datasets.jl
    @createdata, Spiral

include("variables.jl")
include("functions.jl")
include("layers.jl")
include("optimizer.jl")
include("utils.jl")
include("datasets.jl")

end
