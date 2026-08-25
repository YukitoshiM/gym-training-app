export const AI_FEATURE_LIMITS = Object.freeze({
  chat: Object.freeze({
    userMessageCharacters: 300,
    inputCharacters: 10_000,
    outputTokens: 800,
  }),
  planGeneration: Object.freeze({
    generatedMessageCharacters: 4_000,
    inputCharacters: 16_000,
    outputTokens: 1_600,
  }),
  dailyRecommendation: Object.freeze({
    generatedMessageCharacters: 4_000,
    inputCharacters: 12_000,
    outputTokens: 900,
  }),
  mealImage: Object.freeze({
    memoCharacters: 300,
    imageBase64Characters: 8_000_000,
    inputCharacters: 1_500,
    outputTokens: 900,
  }),
  bodyPhoto: Object.freeze({
    memoCharacters: 300,
    imageBase64Characters: 8_000_000,
    maximumImages: 4,
    inputCharacters: 2_000,
    outputTokens: 1_200,
  }),
  weeklyReport: Object.freeze({
    inputCharacters: 16_000,
    outputTokens: 1_400,
  }),
  monthlyReport: Object.freeze({
    inputCharacters: 18_000,
    outputTokens: 1_600,
  }),
});
