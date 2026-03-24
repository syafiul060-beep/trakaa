/**
 * Gaya Google + require-jsdoc bentrok dengan file besar (index.js).
 * Target: parser modern (optional chaining) + aturan aman tanpa rewrite massal.
 */
module.exports = {
  root: true,
  env: {
    es2022: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2022,
  },
  extends: [
    "eslint:recommended",
  ],
  ignorePatterns: [
    "node_modules/**",
    "scripts/**",
  ],
  rules: {
    "no-unused-vars": ["error", {
      "argsIgnorePattern": "^_",
      "varsIgnorePattern": "^_",
    }],
    "no-console": "off",
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
    },
  ],
};
