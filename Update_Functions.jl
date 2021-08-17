using Random, Distributions

include("Helper_Functions.jl")

#############################################
###    Begin defining update functions    ###
#############################################

# Generate indices of individuals leaving the susceptible compartment
function get_new_cases(class)
    this_risk = class["risk"]
    
    this_S = class["S"]
    n_S = length(this_S)

    # Skip this iteration if no susceptibles are present
    n_S != 0 ? nothing : return nothing # Structure is conditional ? true : false

    # Get number of new exposeds
    this_binom = Binomial(n_S, this_risk)
    n_new_cases = rand(this_binom, 1)[1] # Need output to be a scalar, not a length 1 vector

    # Skip the rest of this iteration if no new cases arise
    n_new_cases != 0 ? nothing : return nothing

    # Choose specific new exposeds
    which_new_cases = sample(this_S, n_new_cases, replace=false)
end

function update_S!(status_new, status_old, day)
    # Extract info on current status
    classes_old = status_old["classes"]

    for i in eachindex(classes_old)
        this_class = classes_old[i]

        # If this class doesn't meet on the specified day, skip to next iteration without any updating
        this_class_days = this_class["days"]
        in(day, this_class_days) ? nothing : continue # Structure is conditional ? true : false

        # Skip this iteration if no risk of infection
        this_risk = this_class["risk"]
        this_risk != 0 ? nothing : continue

        # Get indices of new exposeds
        new_cases = get_new_cases(this_class)

        # If no new cases are generated, move on to the next iteration
        isnothing(new_cases) ? continue : nothing

        # Move new infections to the "E" compartment
        # Note: The . applies this function over the vector which_new_cases
        change_compartment!.(Ref(status_new), new_cases, "E")
    end
end


# Moves some fraction of Es to A and/or I.
# Changes are made in status_new, values for computation are obtained from status_old.
# advance_prob_E is the day-wise probability of an E moving to some other compartment
# E_to_A_prob is the proportion of transitions out of E which are to A (the rest go to I)
function update_E!(status_new, status_old, advance_prob_E, E_to_A_prob)
    students_old = status_old["students"]

    # We only need the indices of the students in E. Extract these indices here
    inds_E = get_compartments(students_old, "E")

    # Get number transitioning out out of E
    n_E = length(inds_E)
    if n_E == 0
        return nothing # End the process if there are no exposeds
    end
    this_binom = Binomial(n_E, advance_prob_E)
    n_leaving = rand(this_binom, 1)[1] # Need output to be a scalar, not a length 1 vector

    if n_leaving == 0
        return nothing # End the process here if no transitions occur
    end

    # Choose specific individuals to transition out of E
    #! WARNING: We are sampling indices to students, not indices to inds_E
    which_to_transition = sample(inds_E, n_leaving, replace=false)

    # Choose how many of the transitions are to A and I
    binom_to_A = Binomial(n_leaving, E_to_A_prob)
    n_to_A = rand(binom_to_A, 1)[1] 
    n_to_I = n_leaving - n_to_A

    # Choose individuals and perform transitions to A
    if n_to_A != 0
        which_to_A = sample(which_to_transition, n_to_A, replace=false)
        change_compartment!.(Ref(status_new), which_to_A, "A")
    else
        # Even if no transitions to A occur, still create an empty container so we can do 
        # set arithmetic to get indices transitioning to I
        which_to_A = Vector{Int64}()
    end

    # Choose individuals and perform transitions to I
    if n_to_I != 0
        which_to_I = setdiff(which_to_transition, which_to_A)
        change_compartment!.(Ref(status_new), which_to_I, "I")
    end
end

# Moves some fraction of As to R.
# Changes are made in status_new, values for computation are obtained from status_old.
# recovery_prob_A is the probability of a particular asymptomatic recovering on a specific day
"""
    update_A!(status_new, status_old, advance_prob_A, A_to_R_prob)

Choose a random number of As to move to other compartments using advance_prob_A. 
These individuals are divided between I and R using A_to_R_prob.

Note: It might feel slightly more natural to focus on the A to I transitions than A to R. 
However, this function emphasizes R to make it easier to distinguish function from update_E!. Specifically, Es never move to R, and
As never move to A.
"""
function update_A!(status_new, status_old, advance_prob_A, A_to_R_prob)
    students_old = status_old["students"]

    # We only need the indices of the students in A. Extract these indices here
    inds_A = get_compartments(students_old, "A")

    ### Get number transitioning out out of A
    n_A = length(inds_A)
    n_A != 0 ? nothing : return nothing # End the process if there are no exposeds
    this_binom = Binomial(n_A, advance_prob_A)
    n_leaving = rand(this_binom, 1)[1] # Need output to be a scalar, not a length 1 vector
    n_leaving != 0 ? nothing : return nothing # End the process if no individuals leave A

    # Choose how many of the transitions are to R and I
    binom_to_R = Binomial(n_leaving, A_to_R_prob)
    n_to_R = rand(binom_to_R, 1)[1] 
    n_to_I = n_leaving - n_to_R

    # Choose specific individuals to transition out of A
    #! WARNING: We are sampling indices to students, not indices to inds_A
    which_to_transition = sample(inds_A, n_leaving, replace=false)

    # Choose individuals and perform transitions to R
    if n_to_R != 0
        which_to_R = sample(which_to_transition, n_to_R, replace=false)
        change_compartment!.(Ref(status_new), which_to_R, "R")
    else
        # Even if no transitions to A occur, still create an empty container so we can do 
        # set arithmetic to get indices transitioning to I
        which_to_R = Vector{Int64}()
    end

    # Choose individuals and perform transitions to I
    if n_to_I != 0
        which_to_I = setdiff(which_to_transition, which_to_R)
        change_compartment!.(Ref(status_new), which_to_I, "I")
    end
end

# Moves some fraction of Is to R.
# Changes are made in status_new, values for computation are obtained from status_old.
# recovery_prob_I is the probability of a particular asymptomatic recovering on a specific day
function update_I!(status_new, status_old, recovery_prob_I)
    students_old = status_old["students"]

    # We only need the indices of the students in I. Extract these indices here
    inds_I = get_compartments(students_old, "I")

    # Get number transitioning out out of I
    n_I = length(inds_I)
    if n_I == 0
        return nothing # End the process if there are no exposeds
    end
    this_binom = Binomial(n_I, recovery_prob_I)
    n_leaving = rand(this_binom, 1)[1] # Need output to be a scalar, not a length 1 vector

    if n_leaving == 0
        return nothing # End the process here if no transitions occur
    end

    # Choose specific individuals to transition out of I
    # WARNING: We are sampling indices to students, not indices to inds_I
    which_to_transition = sample(inds_I, n_leaving, replace=false)

    # Update status_new
    change_compartment!.(Ref(status_new), which_to_transition, "R")
end

# Re-compute risks for each class and update the class objects
function update_risk!(status_new, infect_param_A, infect_param_I)
    classes = status_new["classes"]

    # Compute and store new classwise risks
    compute_risk!.(classes, infect_param_A, infect_param_I)
end


# Runs a single time step and update status with parameters drawn from global scope
"""
    one_step!(status_new, status_old, day)

Runs a single time step and update status_new using status_old as reference and parameters drawn from global scope

"""
function one_step!(status_new, status_old, day)
    update_S!(status_new, status_old, day)
    update_E!(status_new, status_old, advance_prob_E, E_to_A_prob)
    update_A!(status_new, status_old, advance_prob_A, A_to_R_prob)
    update_I!(status_new, status_old, recovery_prob_I)
    
    update_risk!(status_new, infect_param_A, infect_param_I)
end

"""
    one_term(status_initial, n_days)

Runs through a full term starting in status_initial and running for the specified number of days.

Output: A vector of compartment sizes.
"""
function one_term(status_initial, n_days)
    # Container to store all compartment counts
    trajectories = Array{Int64}(undef, n_days + 1, num_compartments)
    initial_counts = all_compartment_counts(status_initial)
    trajectories[1,:] = initial_counts

    day = 1

    # Initialize status_old
    status_old = status_initial

    for j ∈ 1:n_days
        # status_new = deepcopy(status_old) # This doesn't appear to be necessary, and takes a lot of time to run.
        status_new = status_old
        one_step!(status_new, status_old, day)

        this_compartment_counts = all_compartment_counts(status_new)
        trajectories[j + 1,:] = this_compartment_counts

        status_old = status_new

        day = (day % week_length) + 1
    end

    trajectories
end

2

### Infects a few initial cases and runs the simulation on a copy of status
### ToDo: Needs unit tests
"""
    run_sim(status, n_initial_cases, n_days)

    Create a copy of status, infect the specified number of initial cases, 
    then generate an infection trajectory and return it as a data frame.
"""
function run_sim(status_raw, n_initial_cases, n_days)
    this_status = deepcopy(status_raw)

    ### Introduce a few initial cases
    n_students = length(this_status["students"])
    inds_infect = sample(1:n_students, n_initial_cases, replace=false)
    change_compartment!.(Ref(this_status), inds_infect, "I")

    ### Compute classwise risks
    compute_risk!.(this_status["classes"], infect_param_A, infect_param_I)


    trajectories_mat = one_term(this_status, n_days)
    trajectories_data = DataFrame(trajectories_mat, all_compartments)
end



"""
    one_parameter_set(status_raw, M, infect_param_A, infect_param_I, advance_prob_E, E_to_A_prob, recovery_prob_A, recovery_prob_I, n_initial_cases)

Run M simulation replicates with the specified parameter values on the provided initialized status object.

# Arguments
- `status_raw`: A status object containing students and classes, but WITHOUT ANY CLASSWISE RISKS
- `M`: Number of times to replicate the simulation
- `infect_param_I`: Proportionality constant for infection probability from infected compartment
- `infect_param_A`: Proportionality constant for infection probability from asymptomatic compartment
- `advance_prob_E`: Probability of an E moving to either A or I on a particular day
- `E_to_A_prob`: Probability that an advancement from E is to A
- `disease_progress_prob`: Proportionality of an A moving to I on a particular day
- `recovery_prob_A`: Probability of an A moving to R on a particular day
- `recovery_prob_I`: Probability of an I moving to R on a particular day
- `n_initial_cases`: Number of students to move to the I compartment before starting each simulation
"""
function one_parameter_set(status_raw, M, 
    infect_param_I, infect_param_A, advance_prob_E, E_to_A_prob, disease_progress_prob, recovery_prob_A, recovery_prob_I,
    n_initial_cases)
    # all_sim_outputs = @showprogress "Running simulation..." [run_sim(status_raw, n_initial_cases, n_days) for i in 1:M];
    all_sim_outputs = Vector{Any}(undef, M)
    for i in 1:M
        all_sim_outputs[i] = run_sim(status_raw, n_initial_cases, n_days)
    end

    return all_sim_outputs
end


# all_risks = [this_status["classes"][i]["risk"] for i in eachindex(classes)]