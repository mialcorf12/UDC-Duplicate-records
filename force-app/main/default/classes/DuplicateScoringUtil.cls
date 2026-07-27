/**
 * @description Utility class for scoring duplicate record pairs.
 *              Implements weighted similarity scoring using Jaro-Winkler for name comparison.
 *
 *              Score weights:
 *                Email   → 40 points (exact lowercase match)
 *                Phone   → 30 points (normalized 7-digit match)
 *                Name    → 20 points (Jaro-Winkler on full name)
 *                Company → 10 points (exact lowercase match)
 *                Total   → 100 points maximum
 */
public with sharing class DuplicateScoringUtil {

    // Score weight constants
    private static final Decimal WEIGHT_EMAIL   = 40;
    private static final Decimal WEIGHT_PHONE   = 30;
    private static final Decimal WEIGHT_NAME    = 20;
    private static final Decimal WEIGHT_COMPANY = 10;

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Scores two SObject records (Contact or Lead) on a 0–100 scale.
     *              Works with both Contact and Lead objects using dynamic field access.
     * @param r1 First SObject (Contact or Lead).
     * @param r2 Second SObject (Contact or Lead).
     * @return Decimal score between 0 and 100.
     */
    public static Decimal scoreRecords(SObject r1, SObject r2) {
        Decimal score = 0;

        // ── Email (40 pts) ──
        String email1 = normalizeEmail((String) r1.get('Email'));
        String email2 = normalizeEmail((String) r2.get('Email'));
        if (String.isNotBlank(email1) && email1.equals(email2)) {
            score += WEIGHT_EMAIL;
        }

        // ── Phone (30 pts) ──
        String phone1 = normalizePhone((String) r1.get('Phone'));
        String phone2 = normalizePhone((String) r2.get('Phone'));
        if (String.isNotBlank(phone1) && phone1.equals(phone2)) {
            score += WEIGHT_PHONE;
        }

        // ── Name (20 pts) — Jaro-Winkler on "FirstName LastName" ──
        String fullName1 = buildFullName(r1);
        String fullName2 = buildFullName(r2);
        if (String.isNotBlank(fullName1) && String.isNotBlank(fullName2)) {
            Decimal jwScore = jaroWinkler(fullName1, fullName2);
            score += WEIGHT_NAME * jwScore;
        }

        // ── Company (10 pts) ──
        String company1 = getCompanyName(r1);
        String company2 = getCompanyName(r2);
        if (String.isNotBlank(company1) && company1.equalsIgnoreCase(company2)) {
            score += WEIGHT_COMPANY;
        }

        return score.setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Normalizes a phone number by stripping all non-digit characters
     *              and returning the last 7 digits.
     * @param phone Raw phone string (may include spaces, dashes, parens, plus).
     * @return Last 7 digits of the stripped number, or empty string if blank.
     */
    public static String normalizePhone(String phone) {
        if (String.isBlank(phone)) {
            return '';
        }
        String digitsOnly = phone.replaceAll('[^0-9]', '');
        if (digitsOnly.length() == 0) {
            return '';
        }
        if (digitsOnly.length() <= 7) {
            return digitsOnly;
        }
        return digitsOnly.right(7);
    }

    /**
     * @description Normalizes an email address by trimming whitespace and lowercasing.
     * @param email Raw email string.
     * @return Lowercased, trimmed email, or empty string if blank.
     */
    public static String normalizeEmail(String email) {
        if (String.isBlank(email)) {
            return '';
        }
        return email.trim().toLowerCase();
    }

    /**
     * @description Computes the Jaro-Winkler similarity score between two strings.
     *              Returns a value in [0.0, 1.0] where 1.0 means identical strings.
     *
     *              Implementation follows the standard Jaro-Winkler algorithm:
     *              1. Compute Jaro similarity
     *              2. Apply Winkler prefix bonus (up to 4-char common prefix, scaling factor p=0.1)
     *
     * @param s1 First string (already normalized/lowercased by caller).
     * @param s2 Second string (already normalized/lowercased by caller).
     * @return Decimal similarity score in [0.0, 1.0].
     */
    public static Decimal jaroWinkler(String s1, String s2) {
        if (s1 == null) { s1 = ''; }
        if (s2 == null) { s2 = ''; }

        if (s1.equals(s2)) {
            return 1.0;
        }
        if (s1.length() == 0 || s2.length() == 0) {
            return 0.0;
        }

        Integer len1 = s1.length();
        Integer len2 = s2.length();

        // Match window = floor(max(len1,len2)/2) - 1
        Integer maxLen = Math.max(len1, len2);
        Integer matchWindow = Math.max(0, (maxLen / 2) - 1);

        Boolean[] s1Matched = new Boolean[len1];
        Boolean[] s2Matched = new Boolean[len2];
        for (Integer i = 0; i < len1; i++) { s1Matched[i] = false; }
        for (Integer i = 0; i < len2; i++) { s2Matched[i] = false; }

        Integer matches = 0;
        Integer transpositions = 0;

        // Count matches
        for (Integer i = 0; i < len1; i++) {
            Integer start = Math.max(0, i - matchWindow);
            Integer end   = Math.min(len2 - 1, i + matchWindow);
            for (Integer j = start; j <= end; j++) {
                if (s2Matched[j]) { continue; }
                if (s1.charAt(i) != s2.charAt(j)) { continue; }
                s1Matched[i] = true;
                s2Matched[j] = true;
                matches++;
                break;
            }
        }

        if (matches == 0) {
            return 0.0;
        }

        // Count transpositions
        Integer k = 0;
        for (Integer i = 0; i < len1; i++) {
            if (!s1Matched[i]) { continue; }
            while (!s2Matched[k]) { k++; }
            if (s1.charAt(i) != s2.charAt(k)) {
                transpositions++;
            }
            k++;
        }

        Decimal matchesDec = matches;
        Decimal jaro =
            (matchesDec / len1 + matchesDec / len2 + (matchesDec - transpositions / 2.0) / matchesDec)
            / 3.0;

        // Winkler prefix bonus (p = 0.1, max prefix length = 4)
        Integer prefixLen = 0;
        Integer maxPrefix = Math.min(4, Math.min(len1, len2));
        for (Integer i = 0; i < maxPrefix; i++) {
            if (s1.charAt(i) == s2.charAt(i)) {
                prefixLen++;
            } else {
                break;
            }
        }

        Decimal jaroWinklerScore = jaro + prefixLen * 0.1 * (1.0 - jaro);
        return jaroWinklerScore.setScale(6, RoundingMode.HALF_UP);
    }

    /**
     * @description Builds a minimal JSON snapshot of the record's key fields.
     *              Only includes: Email, Phone, FirstName, LastName, Company.
     *              Lead uses Company directly; Contact uses Account.Name as "Company".
     *
     * @param record      The SObject record (Contact or Lead).
     * @param objectType  'Contact' or 'Lead'.
     * @return JSON string: {"Email":"...","Phone":"...","FirstName":"...","LastName":"...","Company":"..."}
     */
    public static String buildSnapshotJSON(SObject record, String objectType) {
        Map<String, Object> snapshot = new Map<String, Object>();

        String email     = (String) record.get('Email');
        String phone     = (String) record.get('Phone');
        String firstName = (String) record.get('FirstName');
        String lastName  = (String) record.get('LastName');
        String company   = '';

        if (objectType == 'Lead') {
            company = (String) record.get('Company');
        } else {
            // Contact: traverse the Account relationship
            SObject acct = record.getSObject('Account');
            if (acct != null) {
                company = (String) acct.get('Name');
            }
        }

        snapshot.put('Email',     email     != null ? email     : '');
        snapshot.put('Phone',     phone     != null ? phone     : '');
        snapshot.put('FirstName', firstName != null ? firstName : '');
        snapshot.put('LastName',  lastName  != null ? lastName  : '');
        snapshot.put('Company',   company   != null ? company   : '');

        return JSON.serialize(snapshot);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static String buildFullName(SObject record) {
        String firstName = (String) record.get('FirstName');
        String lastName  = (String) record.get('LastName');
        String fullName  = '';
        if (String.isNotBlank(firstName)) {
            fullName = firstName.trim().toLowerCase();
        }
        if (String.isNotBlank(lastName)) {
            fullName = (String.isNotBlank(fullName) ? fullName + ' ' : '') + lastName.trim().toLowerCase();
        }
        return fullName;
    }

    private static String getCompanyName(SObject record) {
        // For Lead, Company is a direct field
        Object companyObj = record.get('Company');
        if (companyObj != null) {
            return ((String) companyObj).trim().toLowerCase();
        }
        // For Contact, look at Account.Name
        SObject acct = record.getSObject('Account');
        if (acct != null) {
            String name = (String) acct.get('Name');
            if (String.isNotBlank(name)) {
                return name.trim().toLowerCase();
            }
        }
        return '';
    }
}
