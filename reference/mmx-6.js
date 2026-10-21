var VERSION = 6

var ratings = {
    1: 3,
    2: 2,
    3: 1,
    4: 4,
};

function State(difficulty, stability, repeat_long) {
    this.difficulty = difficulty
    this.stability = stability
    this.repeat_long = repeat_long
    this.version = VERSION
}

var target_retention = 0.85

function card_forgetting_curves(response_history, interval_history, content_params, user_params, totalDaysSinceLastReview, lastScheduledDays) {
    if (!validate_input(response_history, interval_history, null, content_params, user_params)) {
        return {"success": false}
    }
    var data = [];
    var states = [];
    var MIN_POINTS = 1000.0;
    var decay = -user_params[20];
    function calculateMaxDays(response_history, interval_history, totalDaysSinceLastReview, lastScheduledDays) {
        if (response_history.length === 0) return 0;
        var daysSinceFirstLearn = 0;
        for (var i = 0; i < interval_history.length; i++) daysSinceFirstLearn += interval_history[i];
        var previewDays = Math.max(lastScheduledDays * 1.5 - totalDaysSinceLastReview, lastScheduledDays * 0.5);
        return Math.min(daysSinceFirstLearn + previewDays, 365);
    }
    var maxDays = calculateMaxDays(response_history, interval_history, totalDaysSinceLastReview, lastScheduledDays);
    for (var i = 0; i < response_history.length; i++) {
        var r = ratings[response_history[i]];
        var t = interval_history[i];
        if (i == 0) states.push(init_state(user_params, r));
        else states.push(next_state(user_params, states[i - 1], r, t));
    }
    if (states.length === 0) return {"success": true, "data": []};
    var step = Math.min(maxDays / MIN_POINTS, 1.0);
    var daysSinceFirstLearn = 0;
    var lastStability = states[0].stability;
    data.push({date: 0, daysSinceFirstLearn: 0, elapsedDaysSinceLastReview: 0, retrievability: 100, stability: lastStability, review_th: 1});
    for (var i = 1; i < response_history.length; i++) {
        var interval = interval_history[i];
        var currentStability = states[i].stability;
        var elapsedDays = 0;
        while (elapsedDays < interval - step) {
            elapsedDays += step;
            var retrievability = forgetting_curve(elapsedDays, lastStability, decay) * 100;
            data.push({date: daysSinceFirstLearn + elapsedDays, daysSinceFirstLearn: daysSinceFirstLearn + elapsedDays, elapsedDaysSinceLastReview: elapsedDays, retrievability: retrievability, stability: lastStability, review_th: i});
        }
        daysSinceFirstLearn += interval;
        data.push({date: daysSinceFirstLearn, daysSinceFirstLearn: daysSinceFirstLearn, elapsedDaysSinceLastReview: 0, retrievability: 100, stability: currentStability, review_th: i});
        lastStability = currentStability;
    }
    var elapsedSinceLastReview = totalDaysSinceLastReview;
    var elapsedDays = 0;
    while (elapsedDays < elapsedSinceLastReview - step) {
        elapsedDays += step;
        var retrievability = forgetting_curve(elapsedDays, lastStability, decay) * 100;
        data.push({date: daysSinceFirstLearn + elapsedDays, daysSinceFirstLearn: daysSinceFirstLearn + elapsedDays, elapsedDaysSinceLastReview: elapsedDays, retrievability: retrievability, stability: lastStability, review_th: interval_history.length});
    }
    var currentRetrievability = forgetting_curve(elapsedSinceLastReview, lastStability, decay) * 100;
    data.push({date: daysSinceFirstLearn + elapsedSinceLastReview, daysSinceFirstLearn: daysSinceFirstLearn + elapsedSinceLastReview, elapsedDaysSinceLastReview: elapsedSinceLastReview, retrievability: currentRetrievability, stability: lastStability, review_th: interval_history.length});
    var currentTime = daysSinceFirstLearn + elapsedSinceLastReview;
    var previewDays = Math.max(maxDays - currentTime, 0);
    var previewDaysElapsed = 0;
    while (previewDaysElapsed < previewDays) {
        previewDaysElapsed += step;
        var retrievability = forgetting_curve(elapsedSinceLastReview + previewDaysElapsed, lastStability, decay) * 100;
        data.push({date: currentTime + previewDaysElapsed, daysSinceFirstLearn: currentTime + previewDaysElapsed, elapsedDaysSinceLastReview: elapsedSinceLastReview + previewDaysElapsed, retrievability: retrievability, stability: lastStability, review_th: interval_history.length});
    }
    return {"success": true, "data": data};
}

function init_state(user_params, rating) {
    var stability = user_params[rating - 1]
    var difficulty = Math.min(Math.max(init_difficulty(user_params, rating), 1), 10)
    return new State(difficulty, stability, 1)
}

function init_difficulty(user_params, rating) {
    return user_params[4] - Math.exp(user_params[5] * (rating - 1)) + 1
}

function next_state(user_params, state, rating, interval) {
    var last_d = state.difficulty
    var last_s = state.stability
    var retrievability = forgetting_curve(interval, last_s, -user_params[20])
    var difficulty = next_difficulty(user_params, last_d, rating)
    var stability
    if (rating <= 2) stability = next_forget_stability(user_params, difficulty, last_s, retrievability, rating)
    else stability = next_recall_stability(user_params, difficulty, last_s, retrievability, rating)
    return new State(difficulty, stability, state.repeat_long + 1)
}

function forgetting_curve(t, s, decay) {
    var factor = Math.pow(0.9, 1 / decay) - 1
    return Math.pow(1 + factor * t / s, decay)
}

function linear_damping(delta_d, old_d) { return delta_d * (10 - old_d) / 9 }

function mean_reversion(user_params, init_value, current_value) {
    return user_params[7] * init_value + (1 - user_params[7]) * current_value
}

function next_difficulty(user_params, difficulty, rating) {
    var delta_d = -user_params[6] * (rating - 3)
    var new_d = difficulty + linear_damping(delta_d, difficulty)
    new_d = mean_reversion(user_params, init_difficulty(user_params, 1), new_d)
    return Math.min(Math.max(parseFloat(new_d.toFixed(2)), 1), 10)
}

function next_recall_stability(user_params, d, s, r, rating) {
    var easy_bonus = rating == 4 ? user_params[16] : 1
    var new_s = s * (1 + Math.exp(user_params[8]) * (11 - d) * Math.pow(s, -user_params[9]) * (Math.exp((1 - r) * user_params[10]) - 1) * easy_bonus)
    return +new_s.toFixed(2)
}

function next_forget_stability(user_params, d, s, r, rating) {
    var again_penalty = rating == 1 ? user_params[15] : 1
    var new_s = (user_params[11] * Math.pow(d, -user_params[12]) * (Math.pow(s + 1, user_params[13]) - 1) * Math.exp((1 - r) * user_params[14]) * again_penalty)
    return +new_s.toFixed(2)
}

function validate_input(response_history, interval_history, sr_state, content_params, user_params) {
    if (!user_params) return false
    if (!content_params) return false
    if (user_params.length != 21) return false
    if (response_history.length < 1) return false
    if (interval_history.length < 1) return false
    if (response_history.length != interval_history.length) return false
    if (Math.min.apply(Math, interval_history) < 0) return false
    return true
}
