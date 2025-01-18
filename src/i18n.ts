import quadrantLocale from "i18next";
import { initReactI18next } from "react-i18next";
import enLocale from "./locales/en.json";
import ukLocale from "./locales/uk.json";
import trLocale from "./locales/tr.json";

quadrantLocale
  .use(initReactI18next) // passes i18n down to react-i18next
  .init({
    resources: {
      en: {
        translation: enLocale,
      },
      uk: {
        translation: ukLocale,
      },
      tr: {
        translation: trLocale,
      },
    },

    lng: "en",
    fallbackLng: "en",

    interpolation: {
      escapeValue: false, // react already safes from xss
    },
  });

export default quadrantLocale;
