// Base URL of the backend API.
// Local: VITE_API_URL is not set, so we use http://localhost:5050
// Server: Jenkins sets VITE_API_URL when it builds the app
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:5050";
