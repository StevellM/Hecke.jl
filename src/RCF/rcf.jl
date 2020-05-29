export kummer_extension, ray_class_field, hilbert_class_field, prime_decomposition_type, defining_modulus

add_verbose_scope(:ClassField)
add_assert_scope(:ClassField)
#set_assert_level(:ClassField, 1)

###############################################################################
#
#  Ray Class Field interface
#
###############################################################################

@doc Markdown.doc"""
    ray_class_field(m::MapClassGrp) -> ClassField
    ray_class_field(m::MapRayClassGrp) -> ClassField
Creates the (formal) abelian extension defined by the map $m: A \to I$
where $I$ is the set of ideals coprime to the modulus defining $m$ and $A$ 
is a quotient of the ray class group (or class group). The map $m$
must be the map returned from a call to {class_group} or {ray_class_group}.
"""
function ray_class_field(m::Union{MapClassGrp, MapRayClassGrp})
  return ray_class_field(m, id_hom(domain(m)))
end

@doc Markdown.doc"""
    ray_class_field(m::Union{MapClassGrp, MapRayClassGrp}, quomap::GrpAbFinGenMap) -> ClassField
For $m$ a map computed by either {ray_class_group} or {class_group} and
$q$ a canonical projection (quotient map) as returned by {quo} for q 
quotient of the domain of $m$ and a subgroup of $m$, create the
(formal) abelian extension where the (relative) automorphism group
is canonically isomorphic to the codomain of $q$.
"""
function ray_class_field(m::S, quomap::T) where {S <: Union{MapClassGrp, MapRayClassGrp}, T}
  domain(quomap) == domain(m) || error("1st map must be a (ray)class group map, and the 2nd must be a projection of the domain of the 1st")
  CF = ClassField{S, T}()
  CF.rayclassgroupmap = m
  D = codomain(quomap)
  S1, mS1 = snf(D)
  iS1 = GrpAbFinGenMap(D, S1, mS1.imap, mS1.map)
  CF.quotientmap = Hecke.compose(quomap, iS1)
  return CF
end

@doc Markdown.doc"""
    hilbert_class_field(k::AnticNumberField) -> ClassField
The Hilbert class field of $k$ as a formal (ray-) class field.
"""
function hilbert_class_field(k::AnticNumberField)
  return ray_class_field(class_group(k)[2])
end

@doc Markdown.doc"""
    ray_class_field(I::NfAbsOrdIdl; n_quo = 0) -> ClassField
The ray class field modulo $I$. If `n_quo` is given, then the largest
subfield of exponent $n$ is computed.
"""
function ray_class_field(I::NfAbsOrdIdl; n_quo = -1)
  return ray_class_field(ray_class_group(I, n_quo = n_quo)[2])
end

@doc Markdown.doc"""
    ray_class_field(I::NfAbsOrdIdl, inf::Array{InfPlc, 1}; n_quo = 0) -> ClassField
The ray class field modulo $I$ and the infinite places given. If `n_quo` is given, then the largest
subfield of exponent $n$ is computed.
"""
function ray_class_field(I::NfAbsOrdIdl, inf::Array{InfPlc, 1}; n_quo = -1)
  return ray_class_field(ray_class_group(I, inf, n_quo = n_quo)[2])
end

###############################################################################
#
#  Number_field interface and reduction to prime power case
#
###############################################################################
@doc Markdown.doc"""
    NumberField(CF::ClassField) -> NfRelNS{nf_elem}

Given a (formal) abelian extension, compute the class field by finding defining
polynomials for all prime power cyclic subfields.

Note, the return type is always a non-simple extension.
"""
function NumberField(CF::ClassField{S, T}; redo::Bool = false, using_norm_relation = false) where {S, T}
  if isdefined(CF, :A) && !redo
    return CF.A
  end
  
  res = ClassField_pp{S, T}[]
  ord = torsion_units_order(base_field(CF))
  G = codomain(CF.quotientmap)
  @assert issnf(G)
  q = GrpAbFinGenElem[G[i] for i=1:ngens(G)]
  for i=1:ngens(G)
    o = G.snf[i]
    lo = factor(o)
    for (p, e) = lo.fac
      q[i] = p^e*G[i]
      S1, mQ = quo(G, q, false)
      if using_norm_relation && !divides(fmpz(ord), order(S1))[1]
        push!(res, ray_class_field_cyclic_pp_Brauer(CF, mQ))
      else
        push!(res, ray_class_field_cyclic_pp(CF, mQ))
      end
    end
    q[i] = G[i]
  end
  CF.cyc = res
  if isempty(res)
    @assert isone(degree(CF))
    Ky = PolynomialRing(base_field(CF), "y", cached = false)[1]
    CF.A = number_field([gen(Ky)-1], check = false, cached = false)[1]
  else
    CF.A = number_field([x.A.pol for x = CF.cyc], check = false, cached = false)[1]
  end
  return CF.A
end

function ray_class_field_cyclic_pp(CF::ClassField{S, T}, mQ::GrpAbFinGenMap) where {S, T}
  @vprint :ClassField 1 "cyclic prime power class field of degree $(degree(CF))\n"
  CFpp = ClassField_pp{S, T}()
  CFpp.quotientmap = compose(CF.quotientmap, mQ)
  CFpp.rayclassgroupmap = CF.rayclassgroupmap
  @assert domain(CFpp.rayclassgroupmap) == domain(CFpp.quotientmap)
  
  @vprint :ClassField 1 "computing the S-units...\n"
  @vtime :ClassField 1 _rcf_S_units(CFpp)
  @vprint :ClassField 1 "finding the Kummer extension...\n"
  @vtime :ClassField 1 _rcf_find_kummer(CFpp)
  @vprint :ClassField 1 "reducing the generator...\n"
  @vtime :ClassField 1 _rcf_reduce(CFpp)
  @vprint :ClassField 1 "descending ...\n"
  @vtime :ClassField 1 _rcf_descent(CFpp)
  return CFpp
end

################################################################################
#
#  Using norm relations to get the s-units
#
################################################################################

function ray_class_field_cyclic_pp_Brauer(CF::ClassField{S, T}, mQ::GrpAbFinGenMap) where {S, T}
  @vprint :ClassField 1 "cyclic prime power class field of degree $(order(codomain(mQ)))\n"
  CFpp = ClassField_pp{S, T}()
  CFpp.quotientmap = compose(CF.quotientmap, mQ)
  CFpp.rayclassgroupmap = CF.rayclassgroupmap
  @assert domain(CFpp.rayclassgroupmap) == domain(CFpp.quotientmap)
  
  e = degree(CFpp)
  v, q = ispower(e)
  k = base_field(CFpp)
  CE = cyclotomic_extension(k, e)
  
  @vprint :ClassField 1 "computing the S-units...\n"
  @vtime :ClassField 1 _rcf_S_units_using_Brauer(CFpp)
  mr = CF.rayclassgroupmap
  mq = CFpp.quotientmap
  KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[CFpp.a])
  ng, mng = norm_group(KK, CE.mp[2], mr)
  attempt = 1
  while !iszero(mng*mq)
    attempt += 1
    @vprint :ClassField 1 "attempt number $(attempt)\n"
    _rcf_S_units_enlarge(CE, CFpp)
    KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[CFpp.a])
    ng, mng = norm_group(KK, CE.mp[2], mr)
  end
  
  @vprint :ClassField 1 "reducing the generator...\n"
  @vtime :ClassField 1 _rcf_reduce(CFpp)
  @vprint :ClassField 1 "descending ...\n"
  @vtime :ClassField 1 _rcf_descent(CFpp)
  return CFpp
end

################################################################################
#
#  S-units computation
#
################################################################################

function _rcf_S_units_enlarge(CE, CF::ClassField_pp)
  lP = CF.sup
  OK = order(lP[1])
  f = maximum(minimum(p) for p in lP)
  for i = 1:5
    f = next_prime(f)
    push!(lP, prime_decomposition(OK, f)[1][1])
  end
  e = degree(CF)
  @vtime :ClassField 3 S, mS = NormRel._sunit_group_fac_elem_quo_via_brauer(nf(OK), lP, e)
  KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[mS(S[i]) for i=1:ngens(S)])
  CF.bigK = KK
  lf = factor(minimum(defining_modulus(CF)[1]))
  lfs = Set(collect(keys(lf.fac)))
  CE.kummer_exts[lfs] = (lP, KK)
  _rcf_find_kummer(CF)
  return nothing
end


function _rcf_S_units_using_Brauer(CF::ClassField_pp)

  f = defining_modulus(CF)[1]
  @vprint :ClassField 2 "Kummer extension with modulus $f\n"
  k1 = base_field(CF)
  
  #@assert Hecke.isprime_power(e)
  @vprint :ClassField 2 "Adjoining the root of unity\n"
  C = cyclotomic_extension(k1, degree(CF))
  @vtime :ClassField 2 automorphisms(C, copy = false)
  G, mG = automorphism_group(C.Ka)
  @vtime :ClassField 3 fl = NormRel.has_useful_brauer_relation(G)
  if fl
    @vtime :ClassField 3 lP, KK = _s_unit_for_kummer_using_Brauer(C, minimum(f))
  else
    lP, KK = _s_unit_for_kummer(C, minimum(f))
  end
  
  CF.bigK = KK
  CF.sup = lP
  _rcf_find_kummer(CF)
  return nothing
end


#This function finds a set S of primes such that we can find a Kummer generator in it.
function _s_unit_for_kummer_using_Brauer(C::CyclotomicExt, f::fmpz)
  
  e = C.n
  lf = factor(f)
  lfs = Set(collect(keys(lf.fac)))
  for (k, v) in C.kummer_exts
    if issubset(lfs, k)
      return v
    end
  end  
  K = absolute_field(C)
  @vprint :ClassField 2 "Maximal order of cyclotomic extension\n"
  ZK = maximal_order(K)
  if isdefined(ZK, :lllO)
    ZK = ZK.lllO
  end
  
  lP = Hecke.NfOrdIdl[]

  for p = keys(lf.fac)
    #I remove the primes that can't be in the conductor
    lp = prime_decomposition(ZK, p)
    for (P, s) in lp
      if gcd(norm(P), e) != 1 || gcd(norm(P)-1, e) != 1
        push!(lP, P)
      end 
    end
  end
  
  if length(lP) < 10
    #add some primes
    pp = f
    while length(lP) < 10
      pp = next_prime(pp)
      lpp = prime_decomposition(ZK, pp)
      if !isone(length(lpp))
        push!(lP, lpp[1][1])
      end
    end
  end
  @vprint :ClassField 3 "Computing S-units with $(length(lP)) primes\n"
  @vtime :ClassField 3 S, mS = NormRel._sunit_group_fac_elem_quo_via_brauer(C.Ka, lP, e)
  KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[mS(S[i]) for i=1:ngens(S)])
  C.kummer_exts[lfs] = (lP, KK)
  return lP, KK
end

###############################################################################
#
#  Find small generator of class group
#
###############################################################################

function find_gens(mR::Map, S::PrimesSet, cp::fmpz=fmpz(1))
# mR: SetIdl -> GrpAb (inv of ray_class_group or Frobenius or so)
  ZK = order(domain(mR))
  R = codomain(mR) 
  sR = GrpAbFinGenElem[]
  lp = elem_type(domain(mR))[]

  q, mq = quo(R, sR, false)
  s, ms = snf(q)
  if order(s) == 1
    return lp, sR
  end
  for p in S
    if cp % p == 0 || index(ZK) % p == 0
      continue
    end
    @vprint :ClassField 2 "doing $p\n"
    lP = prime_decomposition(ZK, p)

    f=R[1]
    for (P, e) = lP
      try
        f = mR(P)
      catch e
        if !isa(e, BadPrime)
          rethrow(e)
        end
        break # try new prime number
      end
      if iszero(mq(f))
        break
      end
      #At least one of the coefficient of the element 
      #must be invertible in the snf form.
      el = ms\f
      to_be = false
      for w = 1:ngens(s)
        if gcd(s.snf[w], el.coeff[w]) == 1
          to_be = true
          break
        end
      end
      if !to_be
        continue
      end
      push!(sR, f)
      push!(lp, P)
      q, mq = quo(R, sR, false)
      s, ms = snf(q)
    end
    if order(q) == 1   
      break
    end
  end
  return lp, sR
  
end

function find_gens_descent(mR::Map, A::ClassField_pp, cp::fmpz)

  ZK = order(domain(mR))
  C = cyclotomic_extension(nf(ZK), degree(A))
  R = codomain(mR) 
  Zk = order(codomain(A.rayclassgroupmap))
  sR = GrpAbFinGenElem[]
  lp = elem_type(domain(mR))[]
  q, mq = quo(R, sR, false)
  s, ms = snf(q)
  
  PPS = A.bigK.frob_gens[1]
  for p in PPS
    P = intersect_prime(C.mp[2], p, Zk)
    local f::GrpAbFinGenElem
    try
      f = mR(P)
    catch e
      if !isa(e, BadPrime)
        rethrow(e)
      end
      break # try new prime number
    end
    if iszero(mq(f))
      continue
    end
    #At least one of the coefficient of the element 
    #must be invertible in the snf form.
    el = ms\f
    to_be = false
    for w = 1:ngens(s)
      if gcd(s.snf[w], el.coeff[w]) == 1
        to_be = true
        break
      end
    end
    if !to_be
      continue
    end
    push!(sR, f)
    push!(lp, P)
    q, mq = quo(R, sR, false)
    s, ms = snf(q)
    if order(s) == divexact(order(R), degree(A.K))
      break
    end
  end
  
  if degree(C.Kr) != 1  
    RR = ResidueRing(FlintZZ, degree(A))
    U, mU = unit_group(RR)
    if degree(C.Kr) < order(U)  # there was a common subfield, we
                              # have to pass to a subgroup

      f = C.Kr.pol
      # Can do better. If the group is cyclic (e.g. if p!=2), we already know the subgroup!
      s, ms = sub(U, GrpAbFinGenElem[x for x in U if iszero(f(gen(C.Kr)^Int(lift(mU(x)))))], false)
      ss, mss = snf(s)
      U = ss
      #mg = mg*ms*mss
      mU = mss * ms * mU
    end
    for i = 1:ngens(U)
      l = Int(lift(mU(U[i])))
      S = PrimesSet(100, -1, degree(A), l)
      found = false
      for p in S
        if mod(cp, p) == 0 || mod(index(ZK), p) == 0
          continue
        end
        @vprint :ClassField 2 "doin` $p\n"
        lP = prime_decomposition(ZK, p)
  
        f = R[1]
        for (P, e) = lP
          lpp = prime_decomposition(C.mp[2], P)
          if divexact(degree(lpp[1][1]), degree(P)) != U.snf[i]
            continue
          end
          try
            f = mR(P)
          catch e
            if !isa(e, BadPrime)
              rethrow(e)
            end
            break
          end
          push!(sR, f)
          push!(lp, P)
          q, mq = quo(R, sR, false)
          s, ms = snf(q)
          found = true
          break
        end
        if found
          break
        end
      end
    end
  end
  
  if order(q) == 1   
    return lp, sR
  end
  
  @vprint :ClassField 3 "Bad Case in Descent\n"
  S = PrimesSet(300, -1)
  for p in S
    if cp % p == 0 || index(ZK) % p == 0
      continue
    end
    @vprint :ClassField 2 "doin` $p\n"
    lP = prime_decomposition(ZK, p)

    f=R[1]
    for (P, e) = lP
      try
        f = mR(P)
      catch e
        if !isa(e, BadPrime)
          rethrow(e)
        end
        break # try new prime number
      end
      if iszero(mq(f))
        continue
      end
      #At least one of the coefficient of the element 
      #must be invertible in the snf form.
      el = ms\f
      to_be = false
      for w = 1:ngens(s)
        if gcd(s.snf[w], el.coeff[w]) == 1
          to_be = true
          break
        end
      end
      if !to_be
        continue
      end
      push!(sR, f)
      push!(lp, P)
      q, mq = quo(R, sR, false)
      s, ms = snf(q)
    end
    if order(q) == 1   
      break
    end
  end
  return lp, sR
end

################################################################################
#
#  S-units computation
#
################################################################################

function _rcf_S_units(CF::ClassField_pp)

  f = defining_modulus(CF)[1]
  @vprint :ClassField 2 "Kummer extension with modulus $f\n"
  k1 = base_field(CF)
  
  #@assert Hecke.isprime_power(e)
  @vprint :ClassField 2 "Adjoining the root of unity\n"
  C = cyclotomic_extension(k1, degree(CF))
  
  #We could use f, but we would have to factor it.
  @vtime :ClassField 3 lP, KK = _s_unit_for_kummer(C, minimum(f))
  CF.bigK = KK
  CF.sup = lP
  return nothing
end

#This function finds a set S of primes such that we can find a Kummer generator in it.
function _s_unit_for_kummer(C::CyclotomicExt, f::fmpz)
  
  e = C.n
  lf = factor(f)
  lfs = Set(collect(keys(lf.fac)))
  for (k, v) in C.kummer_exts
    if issubset(lfs, k)
      return v
    end
  end  
  K = absolute_field(C)
  @vprint :ClassField 2 "Maximal order of cyclotomic extension\n"
  ZK = maximal_order(K)
  @vprint :ClassField 2 "Class group of cyclotomic extension\n"
  c, mc = class_group(ZK)
  allow_cache!(mc)
  @vprint :ClassField 2 "... $c\n"
  c, mq = quo(c, e, false)
  mc = compose(pseudo_inv(mq), mc)
  
  lP = Hecke.NfOrdIdl[]

  for p = keys(lf.fac)
     #I remove the primes that can't be in the conductor
     lp = prime_decomposition(ZK, p)
     for (P, s) in lp
       if gcd(norm(P), e) != 1 || gcd(norm(P)-1, e) != 1
         push!(lP, P)
       end 
     end
  end

  g = Array{GrpAbFinGenElem, 1}(undef, length(lP))
  for i = 1:length(lP)
    g[i] = preimage(mc, lP[i])
  end

  q, mq = quo(c, g, false)
  mc = compose(pseudo_inv(mq), mc)
  
  #@vtime :ClassField 3 
  lP = vcat(lP, find_gens(pseudo_inv(mc), PrimesSet(100, -1))[1])::Vector{NfOrdIdl}
  @vprint :ClassField 2 "using $lP of length $(length(lP)) for S-units\n"
  if isempty(lP)
    U, mU = unit_group_fac_elem(ZK)
    KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[mU(U[i]) for i = 1:ngens(U)])
  else
    #@vtime :ClassField 2 
    S, mS = Hecke.sunit_group_fac_elem(lP)
    #@vtime :ClassField 2 
    KK = kummer_extension(e, FacElem{nf_elem, AnticNumberField}[mS(S[i]) for i=1:ngens(S)])
  end
  C.kummer_exts[lfs] = (lP, KK)
  return lP, KK
end

###############################################################################
#
#  First step: Find the Kummer extension over the cyclotomic field
#
###############################################################################
#=
  next, to piece things together:
    have a quo of some ray class group in k,
    taking primes in k over primes in Z that are 1 mod n
    then the prime is totally split in Kr, hence I do not need to
      do relative splitting and relative ideal norms. I am lazy
        darn: I still need to match the ideals
    find enough such primes to generate the rcg quotient (via norm)
                       and the full automorphism group of the big Kummer

          Kr(U^(1/n))  the "big" Kummer ext
         /
        X(z) = Kr(x^(1/n)) the "target"
      / /
    X  Kr = k(z)  = Ka
    | /             |
    k               |
    |               |
    Q               Q

    this way we have the map (projection) from "big Kummer" to 
    Aut(X/k) = quo(rcg)
    The generator "x" is fixed by the kernel of this map

    Alternatively, "x" could be obtained via Hecke's theorem, ala Cohen

    Finally, X is derived via descent
=#

# mR: GrpAb A -> Ideal in k, only preimage used
# cf: Ideal in K -> GrpAb B, only image
# mp:: k -> K inclusion
# builds a (projection) from B -> A identifying (pre)images of
# prime ideals, the ideals are coprime to cp and ==1 mod n

function build_map(CF::ClassField_pp, K::KummerExt, c::CyclotomicExt)
  #mR should be GrpAbFinGen -> IdlSet
  #          probably be either "the rcg"
  #          or a compositum, where the last component is "the rcg"
  # we need this to get the defining modulus - for coprime testing
  m = defining_modulus(CF)[1]
  ZK = maximal_order(base_ring(K.gen[1]))
  cp = lcm(minimum(m), discriminant(ZK))
  
  Zk = order(m)
  mp = c.mp[2]
  cp = lcm(cp, index(Zk))
  Sp = Hecke.PrimesSet(100, -1, c.n, 1) #primes = 1 mod n, so totally split in cyclo

  #@vtime :ClassField 3 
  lp, sG = find_gens(K, Sp, cp)
  G = K.AutG
  sR = Array{GrpAbFinGenElem, 1}(undef, length(lp))
  #@vtime :ClassField 3 
  for i = 1:length(lp)
    p = intersect_nonindex(mp, lp[i], Zk)
    #Since the prime are totally split in the cyclotomic extension by our choice, we can ignore the valuation of the norm
    #sR[i] = valuation(norm(lp[i]), norm(p))*CF.quotientmap(preimage(CF.rayclassgroupmap, p))
    sR[i] = CF.quotientmap(preimage(CF.rayclassgroupmap, p))
  end
  @hassert :ClassField 1 order(quo(G, sG, false)[1]) == 1
       # if think if the quo(G, ..) == 1, then the other is automatic
       # it is not, in general it will never be.
       #example: Q[sqrt(10)], rcf of 16*Zk
  # now the map G -> R sG[i] -> sR[i] 
  h = hom(sG, sR, check = false)
  @hassert :ClassField 1 !isone(gcd(fmpz(degree(CF)), minimum(m))) || issurjective(h)
  CF.h = h
  return h
end

function _rcf_find_kummer(CF::ClassField_pp{S, T}) where {S, T}

  #if isdefined(CF, :K)
  #  return nothing
  #end
  f = defining_modulus(CF)[1]
  @vprint :ClassField 2 "Kummer extension with modulus $f\n"
  k1 = base_field(CF)
  
  #@assert Hecke.isprime_power(e)
  @vprint :ClassField 2 "Adjoining the root of unity\n"
  C = cyclotomic_extension(k1, degree(CF))
  
  #We could use f, but we would have to factor it.
  #As we only need the support, we save the computation of
  #the valuations of the ideal
  KK = CF.bigK  
  lP = CF.sup
  @vprint :ClassField 2 "building Artin map for the large Kummer extension\n"
  @vtime :ClassField 2 h = build_map(CF, KK, C)
  @vprint :ClassField 2 "... done\n"

  #TODO:
  #If the s-units are not large enough, the map might be trivial
  #We could do something better.
  if iszero(h)
    CF.a = FacElem(one(C.Ka))
    return nothing
  end
  k, mk = kernel(h, false) 
  G = domain(h)
  
  # Now, we find the kummer generator by considering the action 
  # of the automorphisms on the s-units
  # x needs to be fixed by k
  # that means x needs to be in the kernel:
  # x = prod gen[1]^n[i] -> prod (z^a[i] gen[i])^n[i]
  #                            = z^(sum a[i] n[i]) x
  # thus it works iff sum a[i] n[i] = 0
  # for all a in the kernel
  R = ResidueRing(FlintZZ, C.n, cached=false)
  M = change_base_ring(R, mk.map)
  i, l = right_kernel(M)
  @assert i > 0
  n = lift(l)
  e1 = degree(CF)
  N = GrpAbFinGen(fmpz[fmpz(e1) for j=1:nrows(n)])
  s, ms = sub(N, GrpAbFinGenElem[N(fmpz[n[j, ind] for j=1:nrows(n)]) for ind=1:i], false)
  ms = Hecke.make_domain_snf(ms)
  H = domain(ms)
  @hassert :ClassField 1 iscyclic(H)
  o = Int(order(H))
  c = 1
  if o < fmpz(e1)
    c = div(fmpz(e1), o)
  end
  g = ms(H[1])
  @vprint :ClassField 2 "g = $g\n"
  #@vprint :ClassField 2 "final $n of order $o and e=$e\n"
  a = FacElem(Dict{nf_elem, fmpz}(one(C.Ka) => fmpz(1)))
  for i = 1:ngens(N)
    eeee = div(mod(g[i], fmpz(e1)), c)
    if iszero(eeee)
      continue
    end
    mul!(a, a, KK.gen[i]^eeee)
  end
  #a = prod(FacElem{nf_elem, AnticNumberField}[KK.gen[i]^div(mod(g[i], fmpz(e1)), c) for i=1:ngens(N) if !iszero(g[i])])
  #@vprint :ClassField 2 "generator $a\n"
  CF.a = a
  CF.sup_known = true
  CF.o = o
  CF.defect = c
  return nothing
end

###############################################################################
#
#  Descent to K
#
###############################################################################

#This function computes a primitive element for the target extension with the
#roots of unit over the base field and the action of the automorphisms on it.
#The Kummer generator is always primitive! (Carlo and Claus)
function _find_prim_elem(AutA::GrpAbFinGen, AutA_gen::Array{NfRelToNfRelMor{nf_elem,  nf_elem}, 1})
  
  A = domain(AutA_gen[1])
  pe = gen(A)
  auto_v = Vector{Tuple{Hecke.GrpAbFinGenElem, NfRelElem{nf_elem}}}(undef, Int(order(AutA)))
  i = 1
  for j in AutA
    im = grp_elem_to_map(AutA_gen, j, pe)
    auto_v[i] = (j, im)
    i += 1
  end
  Auto = Dict{Hecke.GrpAbFinGenElem, NfRelElem{nf_elem}}(auto_v)
  @vprint :ClassField 2 "have action on the primitive element!!!\n"  
  return pe, Auto
end

function _aut_A_over_k(C::CyclotomicExt, CF::ClassField_pp)
  
  A = CF.K
#= 
    now the automorphism group of A OVER k
    A = k(zeta, a^(1/n))
    we have
     tau: A-> A : zeta -> zeta   and a^(1/n) -> zeta a^(1/n)
   sigma: A-> A : zeta -> zeta^l and a^(1/n) -> (sigma(a))^(1/n)
                                                = c a^(s/n)
     for some c in k(zeta) and gcd(s, n) == 1
    Since A is compositum of the class field and k(zeta), A is abelian over
    k, thus sigma * tau = tau * sigma

    sigma * tau : zeta    -> zeta         -> zeta^l
                  a^(1/n) -> zeta a^(1/n) -> zeta^l c a^(s/n)
    tau * sigma : zeta    -> zeta^l       -> zeta^l
                  a^(1/n) -> c a^(s/n)    -> c zeta^s a^(s/n)
   
    Since A is abelian, the two need to agree, hence l==s and
    c can be computed as root(sigma(a)*a^-s, n)

    This has to be done for enough automorphisms of k(zeta)/k to generate
    the full group. If n=p^k then this is one (for p>2) and n=2, 4 and
    2 for n=2^k, k>2
=#
  e = degree(CF)
  g, mg = unit_group(ResidueRing(FlintZZ, e, cached=false))
  @assert issnf(g)
  @assert (e%8 == 0 && ngens(g)==2) || ngens(g) <= 1
  
  K = C.Ka
  Kr = C.Kr

  if degree(Kr) < order(g)  # there was a common subfield, we
                              # have to pass to a subgroup
    @assert order(g) % degree(Kr) == 0
    f = Kr.pol
    # Can do better. If the group is cyclic (e.g. if p!=2), we already know the subgroup!
    s, ms = sub(g, GrpAbFinGenElem[x for x in g if iszero(f(gen(Kr)^Int(lift(mg(x)))))], false)
    ss, mss = snf(s)
    g = ss
    #mg = mg*ms*mss
    mg = mss * ms * mg
  end

  @vprint :ClassField 2 "building automorphism group over ground field...\n"
  ng = ngens(g)+1
  AutA_gen = Array{Hecke.NfRelToNfRelMor{nf_elem,  nf_elem}, 1}(undef, ng)
  AutA_rel = zero_matrix(FlintZZ, ng, ng)
  zeta = C.mp[1]\(gen(Kr))
  n = degree(A)
  @assert e % n == 0

  @vprint :ClassField 2 "... the trivial one (Kummer)\n"
  tau = hom(A, A, zeta^div(e, n)*gen(A), check = false)
  AutA_gen[1] = tau

  AutA_rel[1,1] = n  # the order of tau

  
  @vprint :ClassField 2 "... need to extend $(ngens(g)) from the cyclo ext\n"
  for i = 1:ngens(g)
    si = hom(Kr, Kr, gen(Kr)^Int(lift(mg(g[i]))), check = false)
    @vprint :ClassField 2 "... extending zeta -> zeta^$(mg(g[i]))\n"
    to_be_ext = hom(K, K, C.mp[1]\(si(image(C.mp[1], gen(K)))), check = false)
    sigma = _extend_auto(A, to_be_ext, Int(lift(mg(g[i]))))
    AutA_gen[i+1] = sigma

    @vprint :ClassField 2 "... finding relation ...\n"
    m = gen(A)
    for j = 1:Int(order(g[i]))
      m = sigma(m)
    end
    # now m SHOULD be tau^?(gen(A)), so sigma^order(g[i]) = tau^?
    # the ? is what I want...
    j = 0
    zeta_i = zeta^mod(div(e, n)*(e-1), e)
    mi = coeff(m, 1)
    @hassert :ClassField 1 m == mi*gen(A) 

    while mi != 1
      mul!(mi, mi, zeta_i)
      j += 1
      @assert j <= e
    end
    @vprint :ClassField 2 "... as tau^$(j) == sigma_$i^$(order(g[i]))\n"
    AutA_rel[i+1, 1] = -j
    AutA_rel[i+1, i+1] = order(g[i])
  end
  CF.AutG = AutA_gen
  CF.AutR = AutA_rel
  return nothing
  
end

struct ExtendAutoError <: Exception end

function _extend_auto(K::Hecke.NfRel{nf_elem}, h::Hecke.NfToNfMor, r::Int = -1)
  @hassert :ClassField 1 iskummer_extension(K)
  #@assert iskummer_extension(K)
  k = base_field(K)
  Zk = maximal_order(k)

  if r != -1
    if degree(K) == 2
      r = 1
    else
      #TODO: Do this modularly.
      zeta, ord = Hecke.torsion_units_gen_order(Zk)
      @assert ord % degree(K) == 0
      zeta = k(zeta)^div(ord, degree(K))
      im_zeta = h(zeta)
      r = 1
      z = deepcopy(zeta)
      while im_zeta != z
        r += 1
        mul!(z, z, zeta)
      end
    end
  end
  
  a = -coeff(K.pol, 0)
  dict = Dict{nf_elem, fmpz}()
  dict[h(a)] = 1
  if r <= div(degree(K), 2)
    add_to_key!(dict, a, -r)
    aa = FacElem(dict)
    @vtime :ClassField 3 fl, b = ispower(aa, degree(K), with_roots_unity = true)
    if !fl
      throw(ExtendAutoError())
    end
    return NfRelToNfRelMor(K, K, h, evaluate(b)*gen(K)^r)
  else
    add_to_key!(dict, a, degree(K)-r)
    aa = FacElem(dict)
    @vtime :ClassField 3 fl, b = ispower(aa, degree(K), with_roots_unity = true)
    if !fl
      throw(ExtendAutoError())
    end
    return NfRelToNfRelMor(K, K, h, evaluate(b)*gen(K)^(r-degree(K)))
  end
end


function _rcf_descent(CF::ClassField_pp)
  if isdefined(CF, :A)
    return nothing
  end

  @vprint :ClassField 2 "Descending ...\n"
               
  e = degree(CF)
  k = base_field(CF)
  CE = cyclotomic_extension(k, e)
  A = CF.K
  CK = absolute_field(CE)
  if degree(CK) == degree(k) 
    #Relies on the fact that, if the cyclotomic extension has degree 1, 
    #the absolute field is equal to the base field
    #There is nothing to do! The extension is already on the right field
    CF.A = A
    CF.pe = gen(A)
    return nothing
  end
  
  Zk = order(codomain(CF.rayclassgroupmap))
  ZK = maximal_order(absolute_field(CE))
  
  n = degree(A)
  #@vprint :ClassField 2 "Automorphism group (over ground field) $AutA\n"
  _aut_A_over_k(CE, CF)
  
  AutA_gen = CF.AutG
  AutA = GrpAbFinGen(CF.AutR)
  # now we need a primitive element for A/k
  # mostly, gen(A) will do
  
  @vprint :ClassField 2 "\nnow the fix group...\n"
  if iscyclic(AutA)  # the subgroup is trivial to find!
    @vprint :ClassField 2 ".. trivial as automorphism group is cyclic\n"
    s, ms = sub(AutA, e, false)
    @vprint :ClassField 2 "computing orbit of primitive element\n"
    pe = gen(A)
    os = NfRelElem{nf_elem}[grp_elem_to_map(AutA_gen, ms(j), pe) for j in s]
  else
    @vprint :ClassField 2 "Computing automorphisms of the extension and orbit of primitive element\n"
    pe, Auto = _find_prim_elem(AutA, AutA_gen)
    @vprint :ClassField 2 ".. interesting...\n"
    # want: hom: AutA = Gal(A/k) -> Gal(K/k) = domain(mq)
    #K is the target field.
    # idea: take primes p in k and compare
    # Frob(p, A/k) and preimage(mq, p)
    @assert n == degree(CF.K)
    
    local canFrob
    let CE = CE, ZK = ZK, n = n, pe = pe, Auto = Auto
      function canFrob(p::NfOrdIdl)

        lP = prime_decomposition(CE.mp[2], p)
        P = lP[1][1]
        F, mF = ResidueFieldSmall(ZK, P)
        Ft = PolynomialRing(F, cached=false)[1]
        mFp = extend_easy(mF, CE.Ka)
        ap = image(mFp, CF.a)
        polcoeffs = Vector{elem_type(F)}(undef, n+1)
        polcoeffs[1] = -ap
        for i = 2:n
          polcoeffs[i] = zero(F) 
        end
        polcoeffs[n+1] = one(F)
        pol = Ft(polcoeffs)
        Ap = ResidueRing(Ft, pol, cached = false)
        xpecoeffs = Vector{elem_type(F)}(undef, n)
        for i = 0:n-1
          xpecoeffs[i+1] = image(mFp, coeff(pe, i))
        end
        xpe = Ft(xpecoeffs)
        imF = Ap(xpe)^norm(p)

        res = GrpAbFinGenElem[]
        for (ky, v) in Auto
          cfs = Vector{fq_nmod}(undef, n)
          for i = 0:n-1
            cfs[i+1] = image(mFp, coeff(v, i))
          end
          xp = Ft(cfs)
          kp = Ap(xp)
          if kp == imF
            push!(res, ky)
            if length(res) >1
              throw(BadPrime(p))
            end
            #return ky
          end
        end
        return res[1]
        error("Frob not found")  
      end
    end
    @vprint :ClassField 2 "finding Artin map...\n"
    #TODO can only use non-indx primes, easy primes...
    cp = lcm([minimum(defining_modulus(CF)[1]), index(Zk), index(ZK)])
    #@vtime :ClassField 2 lp, f1 = find_gens(MapFromFunc(canFrob, IdealSet(Zk), AutA),
    #                  PrimesSet(200, -1), cp)
    lp, f1 = find_gens_descent(MapFromFunc(canFrob, IdealSet(Zk), AutA), CF, cp)
    imgs = GrpAbFinGenElem[image(CF.quotientmap, preimage(CF.rayclassgroupmap, p1)) for p1 = lp]
    h = hom(f1, imgs)
    @hassert :ClassField 1 issurjective(h)
    s, ms = kernel(h, false)
    @vprint :ClassField 2 "... done, have subgroup!\n"
    @vprint :ClassField 2 "computing orbit of primitive element\n"
    os = NfRelElem{nf_elem}[Auto[ms(j)] for j in s]
  end
  
  q, mq = quo(AutA, ms.map, false)
  @assert Int(order(q)) == degree(CF)
  
  #now, hopefully either norm or trace will be primitive for the target
  #norm, trace relative to s, the subgroup

  AT, T = PolynomialRing(A, "T", cached = false)
  local charpoly
  inc_map = CE.mp[1]
  let inc_map = inc_map, mq = mq, AutA_gen = AutA_gen, q = q, T = T, e = e
    function coerce_down(a::NfRelElem{nf_elem})
      @assert a.data.length <= 1
      b = coeff(a, 0)
      c = image(inc_map, b)
      @assert c.data.length <= 1
      return coeff(c, 0)
    end
  
    function charpoly(a::NfRelElem{nf_elem})
      @vtime :ClassField 2 o = NfRelElem{nf_elem}[grp_elem_to_map(AutA_gen, mq(j), a) for j = q]
      @vtime :ClassField 2 f = prod(T-x for x=o)
      @assert degree(f) == length(o)
      @assert length(o) == e
      @vtime :ClassField 2 g = nf_elem[coerce_down(coeff(f, i)) for i=0:e]
      return PolynomialRing(parent(g[1]), cached = false)[1](g)
    end
  end
  
  @vprint :ClassField 2 "trying relative trace\n"
  @assert length(os) > 0
  t = os[1]
  for i = 2:length(os)
    t += os[i]
  end
  CF.pe = t
  #now the minpoly of t - via Galois as this is easiest to implement...
  @vprint :ClassField 2 "char poly...\n"
  f2 = charpoly(t)
  @vprint :ClassField 2 "... done\n"
  
  if !issquarefree(f2)
    os1 = NfRelElem{nf_elem}[elem for elem in os]
    while !issquarefree(f2)
      @vprint :ClassField 2 "trying relative trace of squares\n"
      for i = 1:length(os)
        os1[i] *= os[i]
      end
      t = os1[1]
      for i = 2:length(os)
        t += os1[i]
      end
      CF.pe = t
      #now the minpoly of t - via Galois as this is easiest to implement...
      @vprint :ClassField 2 "min poly...\n"
      f2 = charpoly(t)
      @vprint :ClassField 2 "... done\n"
    end  
  end
  CF.A = number_field(f2, check = false, cached = false)[1]
  return nothing
end


function grp_elem_to_map(A::Array{NfRelToNfRelMor{nf_elem, nf_elem}, 1}, b::GrpAbFinGenElem, pe::NfRelElem{nf_elem})
  res = pe
  for i=1:length(A)
    if b[i] == 0
      continue
    end
    for j=1:b[i]
      res = A[i](res)
    end
  end
  return res
end

###############################################################################
#
#  Reduction of generators
#
###############################################################################

function _rcf_reduce(CF::ClassField_pp)
  #e = order(codomain(CF.quotientmap))
  e = degree(CF)
  e = CF.o
  if CF.sup_known
    CF.a = reduce_mod_powers(CF.a, e, CF.sup)
    CF.sup_known = false
  else
    CF.a = reduce_mod_powers(CF.a, e)
  end
  CF.K = radical_extension(CF.o, CF.a, check = false, cached = false)[1]
  return nothing
end


###############################################################################
#
#  Auxiliary functions (to be moved)
#
###############################################################################

@doc Markdown.doc"""
    ring_class_group(O::NfAbsOrd) 
The ring class group (Picard group) of $O$.    
"""
ring_class_group(O::NfAbsOrd) = picard_group(O)


@doc Markdown.doc"""
    ring_class_field(O::NfAbsOrd) -> ClassField
The ring class field of $O$, ie. the maximal abelian extension ramifed 
only at primes dividing the conductor with the automorphism group
isomorphic to the Picard group.
"""
function ring_class_field(O::NfAbsOrd)
  M = maximal_order(O)
  f = extend(conductor(O), M)
  R, mR = ray_class_group(f)
  P, mP = picard_group(O)
  g, t = find_gens(mR)
  h = hom(t, [mP \ contract(x, O) for x = g], check = true)
  k = kernel(h, true)[1]
  q, mq = quo(R, k)
  return ray_class_field(mR, mq)
end