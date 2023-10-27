# ===================================================================
# Config
# ===================================================================
# 全局常量， 根据要不要对函数求导， 设置 `true` 或 `false`, 默认 `true`
const enable_grad = Ref(true) 

# 只做推理时不求导
macro inference(ex)
    quote
        enable_grad[] = false
        local val = Base.@__tryfinally($(esc(ex)),
        enable_grad[] = true);  
        val
    end
end
# ===================================================================
# 面向变量 `Var` 的工具函数
# ===================================================================
# 针对新数据类型， 扩展已有函数的方法
Base.ndims(v::Var) = ndims(v.value)
Base.size(v::Var) = size(v.value)
Base.size(v::Var, i) = size(v.value, i)
Base.eltype(v::Var)  = eltype(v.value)
Base.length(v::Var) = length(v.value)
Base.show(io::IO, v::Var{T}) where T = println(io, "$T(", v.value, ")")
function Base.show(io::IO, ::MIME"text/plain", v::Var{T}) where T 
    println(io, "$T\n", v.value)
end

Base.promote_rule(::Type{Var{Variable}},::Type{Var{Parameter}}) = Var{Variable}
Base.promote_rule(::Type{Var{Variable}},::Type{Var{Literal}}) = Var{Variable}
Base.promote_rule(::Type{Var{Parameter}},::Type{Var{Literal}}) = Var{Variable}

function Base.convert(::Type{Var{T}},x::Var{S}) where {T, S} 
    T == S ? x : T(x.value,name=x.name)
end
Base.convert(::Type{Var{T}},x::Union{Number, AbstractArray}) where T = T(x)

function Base.getproperty(l::Layer, f::Symbol)
    if f in [:_items, :_params]
        getfield(l, f)
    else
        getindex(getproperty(l, :_items), f)
    end
end

function Base.setproperty!(l::Layer, f::Symbol, v)
    isa(v, Union{Var{Parameter}, Layer}) && push!(l._params, f)
    l._items[f] = v    
end

# 将非变量型数据转换成变量型数据
asvariable(obj) = obj isa Var ? obj : Literal(obj)
# 设置变量的创造者
function setcreator!(v::Var, func::Func)
    v.creator = func
    v.generation = func.generation + 1 
end

# 清除变量的梯度
cleargrad!(v::Var) = (v.grad = nothing)
function cleargrads!(l::Layer)
    for p in params(l)
        cleargrad!(p) 
    end
end

# 查询变量属性
hasvalue(v::Var) = !isnothing(v.value)
hasgrad(v::Var) = !isnothing(v.grad)
hascreator(v::Var) = !isnothing(v.creator)
hasname(v::Var) = !isnothing(v.name)
#= 递归版
function params(l::Layer)  
    ps = Var{Parameter}[]
    for p in l._params
        obj = l._items[p]
        if isa(obj, Layer)
            append!(ps, params(obj))
        else
            push!(ps, obj)
        end
    end
    ps
end
=#
# 循环版
function params(l::Layer)
    ls = Layer[l]
    ps = Var{Parameter}[]
    while !isempty(ls)
        l = pop!(ls)
        for p in l._params
            obj = l._items[p]
            if isa(obj, Layer)
                push!(ls, obj)
            else
                push!(ps, obj)
            end
        end
    end
    ps
end
#
# ===================================================================
# 
# ===================================================================

function numerical_grad(f::Function, x, args...; eps=1e-4)
    x1 = x - eps
    x2 = x + eps
    y1 = f(x1, args...)
    y2 = f(x2, args...)
    return (y2.data .- y1.data) / 2eps
end

# ===================================================================
# 计算图相关函数
# ===================================================================
function _dot_var(v::Var; verbose=false)
    name = hasname(v) ? v.name : ""
    if verbose && hasvalue(v)
        hasname(v) && (name *= ": ")
        name *= string(size(v)) * " " * string(eltype(v))
    end
    return """$(objectid(v)) [label="$name", color=orange, style=filled]\n"""
end

function _dot_func(f::Func)
    func_name = split(string(typeof(f)), ".")[end]
    txt = """$(objectid(f)) [label="$(func_name)", color=lightblue, style=filled, shape=box]\n"""
    for x in f.inputs
        txt *= "$(objectid(x)) -> $(objectid(f))\n"
    end
    for y in f.outputs
        txt *= "$(objectid(f)) -> $(objectid(y))\n"
    end
    return txt
end

function get_dot_graph(output; verbose=true)
    txt = ""
    funcs::Vector{Func} = []
    seen_set = Set()
    addfunc(f) = begin
        if f ∉ seen_set
            push!(funcs, f)
            push!(seen_set, f)
        end
    end
    hascreator(output) || error("There is NO computing graph information in given Variable")
    addfunc(output.creator)
    txt *= _dot_var(output, verbose=verbose)

    while !isempty(funcs)
        f = pop!(funcs)
        txt *= _dot_func(f)

        for x in f.inputs
            txt *= _dot_var(x, verbose=verbose)
            hascreator(x) && addfunc(x.creator)
        end
    end
    return "digraph g {\n" * txt * "}"
end

function plot_dot_graph(output; verbose=false, file="graph.png")
    dot_graph = get_dot_graph(output, verbose=verbose)
    graph_path = tempname() * ".dot"
    open(graph_path, "w") do f
        write(f, dot_graph)
    end

    extension = split(file, ".")[end]
    cmd = `dot $graph_path -T $extension -o $file`
    run(cmd)
end

function plot_dot_graph(model::Layer, inputs...; file="model.png")
    y = model(inputs...)
    plot_dot_graph(y, verbose=true, file=file)
end

# ===================================================================
# 
# ===================================================================


update!(model,opt=SGD(0.01)) = opt(model)
Base.clamp!(p::Variable, lo, hi) = clamp!(p.data, lo, hi)
# ===================================================================
# activation function: sigmoid / relu / softmax / log_softmax / leaky_relu
# ===================================================================


relu(x::Variable) = max(x, 0) #这个激活函数怎么用，后面还要研究

function softmax_simple(x;dims=2)
    x = asvariable(x)
    c = maximum(x.data)  # 选出数据中的最大值
    y = exp(x .- c)      # 减去这个最大值以防止溢出
    sum_y = sum(y, dims=dims)
    return y ./ sum_y
end

function softmax_cross_entropy_simple(x, t)
    x, t = asvariable(x), asvariable(t)
    
    p = softmax_simple(x, dims=2)
    clamp!(p, 1e-15, 1.0)
    log_p = log(p)
    tlog_p = log_p[Colon(),t.data]
    return -sum(tlog_p) ./ length(tlog_p)
end

function initW!(l)
    I, O = l.in_size, l.out_size
    l.W.value = randn(I, O) * sqrt(1/I)
end