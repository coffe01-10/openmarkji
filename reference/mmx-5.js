
const VERSION = 5

const ratings = {
1: 3, //认识
2: 2, //模糊
3: 1, //忘记
4: 4, //熟知
};

class State {
constructor(difficulty, stability, repeat_long) {
  this.difficulty = difficulty
  this.stability = stability
  this.repeat_long = repeat_long
  this.version = VERSION
}
}



const target_retention = 0.85

function main(response_history, interval_history, sr_state, content_params, user_params) {
if(!validate_input(response_history, interval_history, sr_state, content_params, user_params)) {
  return {
      "success": false
  }
}

const last_sr_state = JSON.parse(sr_state)

let state
if (need_cold_start(last_sr_state, interval_history)) {
  // 冷启动
  for (var i = 0; i < response_history.length; i++) {
      let r = ratings[response_history[i]]
      // 本次反馈评分
      let t = interval_history[i]
      // 本次反馈距离上次复习的间隔
      if (i == 0) {
          state = init_state(user_params, r)
      } else {
          state = next_state(user_params, state, r, t)
      }
  }
} else {
  let r = ratings[response_history.slice(-1)]
  let t = interval_history.slice(-1)
  state = next_state(user_params, last_sr_state, r, t)
}
let interval = next_interval(state.stability)

if (!Number.isInteger(interval)) {
  return {
      "success": false
  }
}

return {
  "success": true,
  "next_interval": interval,
  "sr_state": JSON.stringify(state)
}
}

function card_forgetting_curves(response_history, interval_history, content_params, user_params, totalDaysSinceLastReview, lastScheduledDays) {
if(!validate_input(response_history, interval_history, null, content_params, user_params)) {
  return {
      "success": false
  }
}

const data = []
const states = []
const MIN_POINTS = 1000.0

function calculateMaxDays(response_history, interval_history, totalDaysSinceLastReview, lastScheduledDays) {
  if (response_history.length === 0) {
      return 0
  }

  let daysSinceFirstLearn = 0
  for (let i = 0; i < interval_history.length; i++) {
      daysSinceFirstLearn += interval_history[i]
  }

  const previewDays = Math.max(lastScheduledDays * 1.5 - totalDaysSinceLastReview, lastScheduledDays * 0.5)

  return Math.min(daysSinceFirstLearn + previewDays, 365)
}

const maxDays = calculateMaxDays(response_history, interval_history, totalDaysSinceLastReview, lastScheduledDays)

for (let i = 0; i < response_history.length; i++) {
  const r = ratings[response_history[i]]
  const t = interval_history[i]
  if (i === 0) {
      states.push(init_state(user_params, r))
  } else {
      states.push(next_state(user_params, states[i - 1], r, t))
  }
}

if (states.length === 0) {
  return {
      "success": true,
      "data": []
  }
}

const step = Math.min(maxDays / MIN_POINTS, 1.0)
let daysSinceFirstLearn = 0
let lastStability = states[0].stability
let lastDifficulty = states[0].difficulty

data.push({
  date: 0,
  daysSinceFirstLearn: 0,
  elapsedDaysSinceLastReview: 0,
  retrievability: 100,
  stability: lastStability,
  difficulty: lastDifficulty,
  review_th: 1,
})

for (let i = 1; i < response_history.length; i++) {
  const interval = interval_history[i]
  const currentStability = states[i].stability
  const currentDifficulty = states[i].difficulty

  let elapsedDays = 0
  while (elapsedDays < interval - step) {
      elapsedDays += step
      const retrievability = forgetting_curve(elapsedDays, lastStability) * 100
      data.push({
          date: daysSinceFirstLearn + elapsedDays,
          daysSinceFirstLearn: daysSinceFirstLearn + elapsedDays,
          elapsedDaysSinceLastReview: elapsedDays,
          retrievability: retrievability,
          stability: lastStability,
          difficulty: lastDifficulty,
          review_th: i,
      })
  }

  daysSinceFirstLearn += interval
  data.push({
      date: daysSinceFirstLearn,
      daysSinceFirstLearn: daysSinceFirstLearn,
      elapsedDaysSinceLastReview: 0,
      retrievability: 100,
      stability: currentStability,
      difficulty: currentDifficulty,
      review_th: i,
  })

  lastStability = currentStability
  lastDifficulty = currentDifficulty
}

const elapsedSinceLastReview = totalDaysSinceLastReview
let elapsedDays = 0
while (elapsedDays < elapsedSinceLastReview - step) {
  elapsedDays += step
  const retrievability = forgetting_curve(elapsedDays, lastStability) * 100
  data.push({
      date: daysSinceFirstLearn + elapsedDays,
      daysSinceFirstLearn: daysSinceFirstLearn + elapsedDays,
      elapsedDaysSinceLastReview: elapsedDays,
      retrievability: retrievability,
      stability: lastStability,
      difficulty: lastDifficulty,
      review_th: interval_history.length,
  })
}

const currentRetrievability = forgetting_curve(elapsedSinceLastReview, lastStability) * 100
data.push({
  date: daysSinceFirstLearn + elapsedSinceLastReview,
  daysSinceFirstLearn: daysSinceFirstLearn + elapsedSinceLastReview,
  elapsedDaysSinceLastReview: elapsedSinceLastReview,
  retrievability: currentRetrievability,
  stability: lastStability,
  difficulty: lastDifficulty,
  review_th: interval_history.length,
})

const currentTime = daysSinceFirstLearn + elapsedSinceLastReview
const previewDays = Math.max(maxDays - currentTime, 0)
let previewDaysElapsed = 0
while (previewDaysElapsed < previewDays) {
  previewDaysElapsed += step
  const retrievability = forgetting_curve(elapsedSinceLastReview + previewDaysElapsed, lastStability) * 100
  data.push({
      date: currentTime + previewDaysElapsed,
      daysSinceFirstLearn: currentTime + previewDaysElapsed,
      elapsedDaysSinceLastReview: elapsedSinceLastReview + previewDaysElapsed,
      retrievability: retrievability,
      stability: lastStability,
      difficulty: lastDifficulty,
      review_th: interval_history.length,
  })
}

return {
  "success": true,
  "data": data
}
}


function init_state(user_params, rating) {
return new State(user_params[2] - (rating - 1) * user_params[3], 2 ** (user_params[0] + (rating - 1) * user_params[1]), 1)
}


function next_state(user_params, state, rating, interval) {
let last_d = state.difficulty
let last_s = state.stability
let retrievability = forgetting_curve(interval, last_s)
let difficulty = next_difficulty(user_params, last_d, rating)
if (rating == 1 || rating == 2) { // 忘记 or 模糊
  var stability = next_forget_stability(user_params, difficulty, last_s, retrievability)
} else if (rating == 3 || rating == 4) { // 认识或熟知
  var stability = next_recall_stability(user_params, difficulty, last_s, retrievability)
}
return new State(difficulty, stability, state.repeat_long+1)
}

function next_difficulty(user_params, difficulty, rating) {
let new_difficulty = difficulty - (rating - 3) * user_params[4]
new_difficulty = Math.min(Math.max(new_difficulty.toFixed(2), 1), 10)
return new_difficulty
}

function next_forget_stability(user_params, d, s, r) {
return +(user_params[9] * Math.pow(s, user_params[10]) * Math.exp(user_params[11] * (1 - r))).toFixed(2)
}

function next_recall_stability(user_params, d, s, r) {
return +(s * (Math.exp(user_params[5]) * Math.pow(d, user_params[6]) * Math.pow(s, user_params[7]) * (Math.exp(user_params[8] * (1 - r)) - 1) + 1)).toFixed(2)
}

function next_interval(stability) {
return Math.min(Math.max(Math.round(stability * Math.log(target_retention) / Math.log(0.9)), 1), 36500)
}

function forgetting_curve(t, s) {
return Math.exp(Math.log(0.9) * t / s)
}

function validate_input(response_history, interval_history, sr_state, content_params, user_params) {
if (!user_params) {
  return false
}

if (!content_params) {
  return false
}

if (user_params.length != 12) {
  return false
}

if (response_history.length < 1) {
  return false
}

if (interval_history.length < 1) {
  return false
}

if (response_history.length != interval_history.length) {
  return false
}

if (Math.min(...interval_history) < 0) {
  return false
}

return true
}

function need_cold_start(sr_state, interval_history) {
if (!sr_state.hasOwnProperty('stability')) {
  return true
}

if (!sr_state.hasOwnProperty('difficulty')) {
  return true
}

if (!sr_state.hasOwnProperty('repeat_long')) {
  return true
}

if (!sr_state.hasOwnProperty('version')) {
  return true
}

if (sr_state.version != VERSION) {
  return true
}

if (interval_history.length != sr_state.repeat_long + 1) {
  return true
}

return false
}

// Export the main function for different environments
if (typeof module !== 'undefined' && module.exports) {
// Node.js environment
module.exports = { main, card_forgetting_curves };
} else if (typeof window !== 'undefined') {
// Browser environment
window.MM6 = { main, card_forgetting_curves };
}


