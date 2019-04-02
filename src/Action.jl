########## action ############
POMDPs.actions(DP::DrivePOMDP) = [:giveup, :takeover]
POMDPs.n_actions(DP::DrivePOMDP) = 2
function POMDPs.actionindex(DP::DrivePOMDP, a::Symbol)
    if a == :giveup
        return 1
    elseif a == :takeover
        return 2
    end
    error("Invalid action: $a")
end

function Acclimit!(DP::DrivePOMDP, acc::Float64) # will be moved inside function Actiontransform() later
    acc = min(acc, DP.Aset.max)
    acc = max(acc, DP.Aset.min)
end

function ToVref(DP::DrivePOMDP, Car::CarSt)
    step = UInt16(Car.s/DP.Δs)+1
    Vref = DP.Routes[DP.SsInit.Other.r].Vref[step] # the real route of other car is known to other car itself
    acc = IDM(Vego=Car.v, Vfront=Vref, Vref=Vref, Snet=Inf, T=1.0, Amax=DP.Aset.max, Bdec=DP.Aset.comfort)
    acc = Acclimit!(DP, acc)
end

# calculate the acceleration of the ego car using IDM based on stopline
function AccCalculate(DP::DrivePOMDP, Ego::CarSt, Aego::Symbol)
    acc_ego = 0.0
    Vref = DP.Routes[Ego.r].Vref[min(UInt16(floor(Ego.s/DP.Δs)+1), 21)]
    if Ego.s < DP.Stopline # strategy before stop line
        if Aego == :giveup
            acc_ego = IDM(Vego=Ego.v, Vfront=0.0, Vref=Vref, Snet=DP.Stopline-Ego.s, T=0.3, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=0.1)
        elseif Aego == :takeover
            acc_ego = IDM(Vego=Ego.v, Vfront=Vref, Vref=Vref, Snet=Inf, T=1.0, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=0.0)
        else
            error("Transform failed: Invalid Action $Aego !")
        end
    else # strategy after stop line
        if Aego == :giveup # brake with min a
            if Ego.v > 0
                acc_ego = DP.Aset.min
            else
                acc_ego == 0.0
            end
        elseif Aego == :takeover
            acc_ego = IDM(Vego=Ego.v, Vfront=Vref, Vref=Vref, Snet=Inf, T=1.0, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=DP.Smin)
        else
            error("Transform failed: Invalid Action $Aego !")
        end
    end
    return acc_ego
end

# calculate the acceleration of the ego car using IDM based on Other and Ego cars; simulate ACC
function AccCalculate(DP::DrivePOMDP, Ego::CarSt, Other::CarSt, Aego::Symbol, Δs::Float64)
    acc_ego = 0.0
    Vref = DP.Routes[Ego.r].Vref[min(UInt16(floor(Ego.s/DP.Δs)+1), 21)]
    if Aego == :giveup # if giveup, ego car follows other car
        acc_ego = IDM(Vego=Ego.v, Vfront=min(Vref, Other.v), Vref=Vref, Snet=Δs, T=0.8, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=DP.Smin)
    elseif Aego == :takeover # if take over, ego car drives as on free road.
        acc_ego = IDM(Vego=Ego.v, Vfront=Vref, Vref=Vref, Snet=Inf, T=1.0, Amax=DP.Aset.max, Bdec=DP.Aset.comfort, Smin=DP.Smin)
    else
        error("Transform failed: Invalid Action $Aego !")
    end
    return acc_ego
end
