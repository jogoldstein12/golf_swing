/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Warm bone-white canvas system — never pure white/black.
        bone: '#F5F3EE',
        paper: '#FCFBF8',
        sand: '#EBE7DE',
        ink: '#191712',
        'ink-70': 'rgba(25,23,18,0.70)',
        'ink-45': 'rgba(25,23,18,0.45)',
        'ink-25': 'rgba(25,23,18,0.25)',
        'ink-08': 'rgba(25,23,18,0.08)',
        // Single signature accent — used sparingly, only for live measurement + primary action.
        fairway: '#B4E019',
        'fairway-deep': '#8FB80F',
        pine: '#1F3D2F',
      },
      fontFamily: {
        // Instrument Serif — editorial, human, current. Wordmark + display numerals + pull-quotes.
        display: ['"Instrument Serif"', 'ui-serif', 'Georgia', 'serif'],
        // Hubot Sans — warm, slightly-robotic geometric. All UI + technical readouts.
        sans: ['"Hubot Sans Variable"', '"Hubot Sans"', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      letterSpacing: {
        label: '0.18em',
      },
      boxShadow: {
        // Soft, diffused ambient shadow — the "light glass" float.
        float: '0 1px 2px rgba(25,23,18,0.04), 0 12px 32px -12px rgba(25,23,18,0.14)',
        'float-lg': '0 2px 4px rgba(25,23,18,0.04), 0 40px 80px -32px rgba(25,23,18,0.22)',
      },
      borderRadius: {
        card: '26px',
      },
    },
  },
  plugins: [],
}
