function sv_next!(Car::CarSt, a::Float64, Δt::Float64)
    Car.s += Car.v*Δt + Δt^2*a/2
    Car.v += Δt*a
    return nothing
end

function sv_next(Car::CarSt, a::Float64, Δt::Float64)
    Car_next = deepcopy(Car)
    sv_next!(Car_next, a, Δt)
    return Car_next
end

########## transition ########
# generate the probability of ending in state x' when executing action a in state x
function POMDPs.transition(DP::DrivePOMDP, Ss::Sts, Aego::Symbol)
    acc_k = 0.0
    akV = [e for e in DP.Aset.min:DP.Aset.max]
    acc_distribution = DiscreteND1D(acc_k, DP.Aset.comfort/2, akV, 1.0)
    PD = zeros(POMDPs.n_states(DP))
    for (i, ak) in enumerate(akV)
        if acc_distribution[i] > 1.0e-2
            result = IDMtransit(DP, Ss, Aego, ak)
            SIndex = POMDPs.stateindex(DP, Sts(result.Ego, result.Other)) # round is made in stateindex()
            PD[SIndex] += acc_distribution[i]
        end
    end
    normalize!(PD, 1)
    #return DiscreteBelief(DP, PD) # toooooo slow
    return SparseCat(DP.SSpace, PD)
end

function IDMtransit(DP::DrivePOMDP, Ss::Sts, Aego::Symbol, acc_k::Float64)

    #if (Ss.Ego.s <= 0.0 && Ss.Ego.v <= 0.0 && Aego == :giveup) || (Ss.Other.s <= 0.0 && Ss.Other.v <= 0.0 && acc_k <= 0.0)
    if (Ss.Ego.v <= 0.0 && Aego == :giveup) || (Ss.Other.v <= 0.0 && acc_k <= 0.0)
        return (Ego=Ss.Ego, Other=Ss.Other, accs=zeros(Int64(DP.Δt/0.1)))
    end

    Ego = deepcopy(Ss.Ego)
    Other = deepcopy(Ss.Other)
    accVec = Vector{Float64}()
    overlap = false
    dist1 = 0.0
    distk = 0.0

    if haskey(DP.Routes[Ego.r].intersect_Infos, Other.r)
        PtDistVec1 = DP.Routes[Ego.r].intersect_Infos[Other.r]
        if length(PtDistVec1) > 1 && PtDistVec1[2][1] == "overlap"
            dist1 = PtDistVec1[2][3]
            distk = DP.Routes[Other.r].intersect_Infos[Ego.r][2][3]
            overlap = true
        end
    end

    for i in 0:Int64(DP.Δt/0.1)-1 # update the state of EgoCar
        acc_ego = 0.0
        if overlap # stop line no longer needed.
            Δs = Other.s - Ego.s + dist1 - distk
            if Δs < DP.Smin # means ego car can not follow other car, ACC mode no longer appliable
                if Aego == :giveup # brakes with min a
                    acc_ego = DP.Aset.min
                else # :takeover # drives freely
                    Vref = DP.Routes[Ego.r].Vref[min(UInt16(floor(Ego.s/DP.Δs)+1), 21)]
                    acc_ego = IDM(Vego=Ego.v, Vfront=Vref, Vref=Vref, Snet=Inf, T=0.1, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=DP.Smin)
                end
            else # means ego car can follow other car now.
                acc_ego = AccCalculate(DP, Ego, Other, Aego, Δs)
            end

        else # no overlap
            acc_ego = AccCalculate(DP, Ego, Aego) # only based on stopline, the state of other car is not relative
            acc_ego = Acclimit!(DP, acc_ego)
        end
        push!(accVec, acc_ego)
        #@show acc_ego
        sv_next!(Ego, acc_ego, 0.1)
        sv_boundry!(DP, Ego)
        sv_next!(Other, acc_k, 0.1)
        sv_boundry!(DP, Other)
        #@show Ego
        #@show Other
    end
    CSRound!(Ego, DP.Δs, DP.Δv)
    return (Ego=Ego, Other=Other, accs=accVec)
end
