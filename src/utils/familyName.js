/**
 * Utility function to format family names for display
 * Removes underscore and numbers after it for cleaner UI display
 * Example: "Arun family_1625406878594" -> "Arun family"
 */

export const formatFamilyNameForDisplay = (familyName) => {
  if (!familyName) return familyName;
  
  // Split by underscore and take only the first part
  const parts = familyName.split('_');
  return parts[0];
};

export const formatFamilyNamesForDisplay = (familyNames) => {
  if (!Array.isArray(familyNames)) return familyNames;
  
  return familyNames.map(formatFamilyNameForDisplay);
};
