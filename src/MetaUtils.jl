@static if false
    local TypeAnnotation, none, symbol, expr
end

@sum_type TypeAnnotation :hidden begin
    none 
    symbol(::Symbol)
    expr(::Expr)
end

function type_annotation(t)
    if t isa Symbol
        return TypeAnnotation'.symbol(t)
    end
    return TypeAnnotation'.expr(t)
end


struct FuncArg
    name::Symbol
    type_annotation::TypeAnnotation
end
function FuncArg(arg)
    name, type_ann = if arg isa Symbol
            (arg, TypeAnnotation'.none)
        elseif arg.head == :(::) && length(arg.args) == 1
            (gensym(:arg), type_annotation(first(arg.args)))
        elseif arg.head == :(::) && length(arg.args) == 2
            (arg.args[1], type_annotation(arg.args[2]))
        else
            error(lazy"Unknown arg type $arg")
        end
    return FuncArg(name, type_ann)
end

function get_type_annotation(f::FuncArg)
    return @cases f.type_annotation begin
        none => :Any
        symbol(x) => x
        expr(x) => x
    end
end

get_name(f::FuncArg) = f.name


"""
Holds the information about a method required by the interface
"""
struct RequiredFunctionality
    interface_name::Union{Symbol, Expr}
    interface_type_vars::Union{Vector{Expr}}
    name::Expr
    args::Union{Vector{FuncArg}}
    func::JLFunction
end
function RequiredFunctionality(required_func, interface_name, type_vars)
    return RequiredFunctionality(
        interface_name, 
        type_vars, 
        esc(required_func.name), 
        FuncArg.(required_func.args),
        required_func
        )
end

function get_arg_names(req_method_def::RequiredFunctionality)
    return get_name.(req_method_def.args::Vector{FuncArg})
end
function get_arg_types(req_method_def::RequiredFunctionality)
    return get_type_annotation.(req_method_def.args)
end

function get_full_struct_name(jl_struct::JLStruct)
    return if length(jl_struct.typevars) == 0
        jl_struct.name
    else
        Expr(:curly, jl_struct.name, jl_struct.typevars...)
    end
end

"""
all the interface methods listed in the body of the struct get put into jl_struct.misc as Expr

Here we turn each Expr into a RequiredFunctionality.
"""
function extract_required_functionality(jl_struct::JLStruct)
    interface_name = if length(jl_struct.typevars) == 0
        jl_struct.name
    else
        Expr(:curly, jl_struct.name, jl_struct.typevars...)
    end
    
    escaped_type_vars = jl_struct.typevars isa Nothing ? nothing : Expr[esc(t) for t in jl_struct.typevars]
    return create_required_functionality.(jl_struct.misc, Ref(esc(interface_name)), Ref(escaped_type_vars))
end



function extract_arg_types(m::Method)
    sig_types = fieldtypes(m.sig)
    return sig_types[2:end]
end

function arg_with_interface_type_check(func_arg::FuncArg)
    t_ann = get_type_annotation(func_arg)
    return :($t_ann <: $InterfaceKind ? Any : $t_ann)
end

function arg_with_interface_wrap_check(func_arg::FuncArg)
    return @cases func_arg.type_annotation begin
        none => :($(func_arg.name)::Any)
        [symbol, expr](type_param) => :($(func_arg.name)::($type_param <: $InterfaceKind ? $Interface{$type_param, <:Any} : $type_param))
    end
end

"""
This takes the arg annotations passed to the @interface macro and wraps them in a check for if the
the type is `This` or any other interface. Then it switches them out for an Interface{...} wrap
"""
function arg_with_this_check(func_arg::FuncArg, interface_name)
    return @cases func_arg.type_annotation begin
        none => :($(func_arg.name)::Any)
        [symbol, expr](type_param) => :($(func_arg.name)::$(make_this_check_annotation(type_param, interface_name)))
    end
end

function make_this_check_annotation(type_param, interface_name)
    esc_type_param = esc(type_param)
    return :(
        # This should be replaced by the interface
        if $(esc_type_param) <: $This
            $Interface{$(esc(interface_name)), <:Any}
        # Other interfaces should be replaced with an Interfae wrap
        elseif $(esc_type_param) <: $InterfaceKind
            $Interface{$(esc_type_param), <:Any}
        else
            $(esc_type_param)
        end
        )
end

"""
Check if an expression is either `This` or `This{...}` (This{...} is not yet supported)
"""
function is_This(type_ann)
    if type_ann isa Symbol
        return type_ann == :This
    elseif type_ann isa Expr
        if type_ann.head == :curly && type_ann.args[1] == :This
            error("Type params in This are not yet supported")
        end
    end
    return false
end

@testitem "Meta Utils" begin
    using ExproniconLite: JLFunction, @test_expr
    using SumTypes
    jlf = JLFunction(:(f(a, b::Int, c::Vector{Int}) = nothing))
    func_args = InterfaceDispatch.FuncArg.(jlf.args)
    function unpack(func_arg)
        variant, content = @cases func_arg.type_annotation begin
            none    => (:none, nothing)
            symbol(x)  => (:symbol, x) 
            expr(x)    => (:expr, x)
        end
        return (func_arg.name, variant, content)
    end
    @test unpack.(func_args) == [
        (:a, :none, nothing),
        (:b, :symbol, :Int),
        (:c, :expr, :(Vector{Int}))
    ]

    jlf = JLFunction(:(f(a, b::Int, c::Vector{T}) where T = "hi!"))
    func_args = InterfaceDispatch.FuncArg.(jlf.args)
    annotation_checks = InterfaceDispatch.arg_with_interface_type_check.(func_args)

    @test_expr annotation_checks[1] == :((Any<:$(InterfaceDispatch.InterfaceKind) ? Any : Any))
    @test_expr annotation_checks[2] == :((Int<:$(InterfaceDispatch.InterfaceKind) ? Any : Int))
    @test_expr annotation_checks[3] == :((Vector{T}<:$(InterfaceDispatch.InterfaceKind) ? Any : Vector{T}))
end


