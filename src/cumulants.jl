# ---- following code is used to caclulate moments ----

""" Center each column of matrix (substracts column's mean).

Input: data in a matrix form.

Returns: matrix with centred columns.
"""
function center!{T<:AbstractFloat}(data::Matrix{T})
  for i = 1:size(data, 2)
    @inbounds data[:,i] = data[:,i]-mean(data[:,i])
  end
end

function center{T<:AbstractFloat}(data::Matrix{T})
  centered = copy(data)
  center!(centered)
  centered
end

""" Calculates the single element of moment's tensor.

Input: v - vectors of data to be multipled and contracted.

Returns: Float64 - element of moment's tensor.
"""
momentel{T <: AbstractFloat}(v::Vector{T}...) =
  mean(mapreduce(i -> v[i], .*, 1:length(v)))

"""Calculate a single block of moment's tensor.

Input: Y - matrices of data, dims - tuple of their sizes.

Returns: Array{N}, a block, where N = size(dims).
"""
function momentseg{T <: AbstractFloat}(dims::Tuple, Y::Matrix{T}...)
  n = length(Y)
  ret = zeros(T, dims)
  for i = 1:prod(dims)
    ind = ind2sub((dims), i)
    @inbounds ret[ind...] = momentel(map(k -> Y[k][:,ind[k]], 1:n)...)
  end
  ret
end

"""Calculate n'th moment in the bs form.

Input: X - matrix of data, n - moment's order, s - number of blocks.

Returns: n - dimentional tensor in blocks.
"""
function momentbs{T <: AbstractFloat}(X::Matrix{T}, n::Int, s::Int)
    M = size(X,2)
    sizetest(n, s) #prepare test
    g = ceil(Int, M/s)
    range = ((1:n)...)
    ret = NullableArray(Array{T, n}, fill(g, n)...)
    for i in indices(n, g)
      Y = map(k -> X[:,seg(i[k], s, M)], 1:n)
      dims = map(i -> (size(Y[i], 2)), range)
      @inbounds ret[i...] = momentseg(dims, Y...)
    end
    SymmetricTensor(ret)
end

# ---- following code is used to caclulate cumulants----
"""Splits indices into given partition.

Input: n - array of indices, part - (Vector{Vector}) partition.

Returns: Vector{Vector} - splited indices.
"""
splitind(n::Vector{Int}, part::Vector{Vector{Int}}) = map(p->n[p], part)

"""Calculates outer product of segments, given partition od indices.

Input: s - Int, size of segment, s^n - size of output segment,
part - (Vector{Vector}) - partition of indices, c - arrays of segments.

Returns: Array{n} - segoent of size s^n.
"""
function prodblocks{T <: AbstractFloat}(s::Int, n::Int, part::Vector{Vector{Int}}, c::Array{T}...)
  ret = zeros(T, fill(s, n)...)
  for i = 1:(s^n)
    ind = ind2sub((fill(s, n)...), i)
    pe = splitind(collect(ind), part)
    @inbounds ret[ind...] = mapreduce(i -> c[i][pe[i]...], *, 1:size(part, 1))
  end
  ret
end

"""Create all partitions of sequence 1:n into sigma subs multi indices
with at least 2 elements each.

Returns: p - Vector{Vector{Vector}}, vector of partitions,
r - Vector{Vector}, number of elements in each partition,
number of partitions.
"""
function indpart(n::Int, sigma::Int)
    p = Vector{Vector{Int}}[]
    r = Vector{Int}[]
    for part in partitions(1:n, sigma)
      s = map(length, part)
      if !(1 in s)
        push!(p, part)
        push!(r, s)
      end
    end
    p, r, length(r)
end

"""Used to handle unregular case if last blocks are not squared.
Makes it square by adding slices with zeros.

Input: inputbox - box with non regular size, s - its new size.

Returns: box of size s^N.
"""
function addzeros{T <: AbstractFloat, N}(s::Int, inputbox::Array{T,N})
  if !all(collect(size(inputbox)) .== s)
    ret = zeros(T, fill(s, N)...)
    ind = map(k -> 1:size(inputbox,k), 1:N)
    @inbounds ret[ind...] = inputbox
    return ret
  end
  inputbox
end

"""Calculates the outer products of cumulants lower order cumulants.

Input: n - order of result cumulants, sigma - number of input cumulants,
c - array of input cumullants of order 2, ..., n-2.

Output: n order symmetric tensor in block form.
"""
function outerp{T <: AbstractFloat}(n::Int, sigma::Int, c::SymmetricTensor{T}...)
  s,g,M = size(c[1])
  p, r, len = indpart(n, sigma)
  ret = NullableArray(Array{T, n}, fill(g, n)...)
  issquare = (s*g==M)
  for i in indices(n, g)
    temp = zeros(T, fill(s, n)...)
    for j in 1:len
      pe = splitind(collect(i), p[j])
      if !issquare && (g in i)
        @inbounds temp += prodblocks(s, n, p[j], map(l -> addzeros(s[1], c[r[j][l]-1].frame[pe[l]...].value), 1:sigma)...)
      else
        @inbounds temp += prodblocks(s, n, p[j], map(l -> c[r[j][l]-1].frame[pe[l]...].value, 1:sigma)...)
      end
    end
    if !issquare && (g in i)
      range = map(k -> ((g == i[k])? (1:(M%s)) : (1:s)), (1:length(i)))
      @inbounds temp = temp[range...]
    end
    @inbounds ret[i...] = temp
  end
  SymmetricTensor(ret)
end

"""Calculates n'th cumulant.

Input: X - matrix of (centred) data, n - the order of the cumulant,
s - number of blocks, c - array of input cumullants of order 2, ..., n-2.

Output: n order symmetric cumulant tensor in block form."""
function cumulantn{T <: AbstractFloat}(X::Matrix{T}, n::Int, s::Int, c::SymmetricTensor{T}...)
  ret =  momentbs(X, n, s)
  for sigma in 2:floor(Int, n/2)
    @inbounds ret -= outerp(n, sigma, c...)
  end
  ret
end

"""Recursive formula, calculate cumulants up to given order.

Input: X - matrix of data, n - given order, s - number of blocks.

Returns array of cumullants of order 2, ..., n, in block form."""
function cumulants{T <: AbstractFloat}(X::Matrix{T}, n::Int, s::Int = 3)
  X = center(X)
  ret = Array(SymmetricTensor{T}, n-1)
  for i = 2:n
    @inbounds ret[i-1] =  (i < 4)? momentbs(X, i, s) : cumulantn(X, i, s, ret[1:(i-3)]...)
  end
  ret
end
