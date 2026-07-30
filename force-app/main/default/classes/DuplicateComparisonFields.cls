/**
 * @description Single source of truth for the Contact/Lead field lists used across
 *              duplicate detection, scoring, snapshot building, and merge. Selectors
 *              and the detection batch build their SELECT column lists from these
 *              constants instead of each duplicating its own copy of the same fields.
 */
public class DuplicateComparisonFields {

    /**
     * @description Canonical comparison-table key representing the block-level,
     *              object-type-aware Address field (MailingAddress on Contact,
     *              Address on Lead).
     */
    public static final String ADDRESS_KEY = 'Address';

    /**
     * @description Contact fields required for duplicate detection blocking,
     *              scoring, and the field comparison snapshot.
     */
    public static final List<String> CONTACT_SNAPSHOT_FIELDS = new List<String>{
        'Id',
        'Email',
        'Phone',
        'MobilePhone',
        'FirstName',
        'LastName',
        'AccountId',
        'Account.Name',
        'Email_Block__c',
        'Phone_Block__c',
        'Name_Block__c',
        'Sales_Informed_Agreement_Signed__c',
        'Email_Collection__c',
        'Portal_User_ID__c'
    };

    /**
     * @description Lead fields required for duplicate detection blocking,
     *              scoring, and the field comparison snapshot.
     */
    public static final List<String> LEAD_SNAPSHOT_FIELDS = new List<String>{
        'Id',
        'Email',
        'Phone',
        'MobilePhone',
        'FirstName',
        'LastName',
        'Company',
        'IsConverted',
        'Email_Block__c',
        'Phone_Block__c',
        'Name_Block__c',
        'Sales_Informed_Agreement_Signed__c',
        'Email_Collection__c',
        'Portal_User_ID__c'
    };

    /**
     * @description Returns the canonical Address block snapshot keys (e.g.
     *              "AddressStreet", "AddressCity") used by DuplicateScoringUtil's
     *              snapshot JSON and, in turn, by the comparison table's field
     *              override map. These are snapshot-only keys, neither Contact
     *              nor Lead expose a field with these exact API names, so merge
     *              code must exclude them from any generic SObject.put() loop and
     *              rely on mergeAddressField() to write the real Mailing/plain
     *              address fields instead.
     * @return Set of canonical Address snapshot keys (not including the plain
     *         "Address" display key itself, callers combine both).
     */
    /**
     * @description Snapshot keys whose real Apex field type is not String (e.g.
     *              Sales_Informed_Agreement_Signed__c is a Date field on both
     *              Contact and Lead). SObject.put(fieldName, stringValue) does not
     *              coerce String into these types, so merge code must special-case
     *              them instead of feeding the snapshot string straight into put().
     */
    public static final Set<String> DATE_SNAPSHOT_FIELDS = new Set<String>{
        'Sales_Informed_Agreement_Signed__c'
    };

    public static Set<String> addressSnapshotKeys() {
        List<String> suffixes = new List<String>{
            'Street', 'City', 'State', 'PostalCode', 'Country', 'Latitude', 'Longitude', 'GeocodeAccuracy'
        };
        Set<String> keys = new Set<String>();
        for (String suffix : suffixes) {
            keys.add(ADDRESS_KEY + suffix);
        }
        return keys;
    }

    /**
     * @description Returns the compound address subfield API names for the given
     *              object type. Contact exposes the address as MailingAddress
     *              subfields; Lead exposes it as plain Address subfields. Callers
     *              use this to select the correct source/target columns when
     *              reading or writing the block-level Address field.
     * @param objectType 'Contact' or 'Lead'.
     * @return List of address subfield API names for the given object type.
     */
    public static List<String> addressSubfields(String objectType) {
        if (objectType == 'Lead') {
            return new List<String>{
                'Street',
                'City',
                'State',
                'PostalCode',
                'Country',
                'Latitude',
                'Longitude',
                'GeocodeAccuracy'
            };
        }
        return new List<String>{
            'MailingStreet',
            'MailingCity',
            'MailingState',
            'MailingPostalCode',
            'MailingCountry',
            'MailingLatitude',
            'MailingLongitude',
            'MailingGeocodeAccuracy'
        };
    }

    private DuplicateComparisonFields() {}
}
