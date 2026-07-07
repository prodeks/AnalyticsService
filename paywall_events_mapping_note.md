# Paywall events mapping note

Transition: first app build on version **2.0.7**.

From this build, paywall and purchase analytics events no longer encode the purchase engine in the event name. Old `adapty_` and `storekit_` prefixes are discontinued; the engine is sent as `purchase_service` with value `adapty` or `storekit`.

## Canonical mapping

| Old event name | New event name |
|---|---|
| `adapty_pricesFailed`, `storekit_pricesFailed` | `prices_load_failed` |
| `adapty_paywallFailed`, `storekit_paywallFailed` | `paywall_show_failed` |
| `adapty_paywall_fetch_error`, `storekit_paywall_fetch_error` | `paywall_fetch_failed` |
| `adapty_purchaseFailed`, `storekit_purchaseFailed` | `purchase_failed` |
| `adapty_restoreFailed`, `storekit_restoreFailed` | `restore_failed` |
| `adapty_PaywallOpenEvent_<paywall_id>`, `storekit_PaywallOpenEvent_<paywall_id>` | `paywall_shown` |
| `adapty_PaywallClosedEvent_<paywall_id>`, `storekit_PaywallClosedEvent_<paywall_id>` | `paywall_closed` |
| `adapty_paywall_checkout_initiated`, `storekit_paywall_checkout_initiated` | `paywall_checkout_initiated` |
| `adapty_paywall_checkout_cancelled`, `storekit_paywall_checkout_cancelled` | `paywall_checkout_cancelled` |
| `adapty_sale_confirmation_success`, `storekit_sale_confirmation_success` | `sale_confirmation_success` |
| `adapty_sale_confirmation_cancel`, `storekit_sale_confirmation_cancel` | `sale_confirmation_cancel` |
| `adapty_sale_confirmation_fail`, `storekit_sale_confirmation_fail` | `sale_confirmation_fail` |
| `adapty_sale_confirmation_restore`, `storekit_sale_confirmation_restore` | `sale_confirmation_restore` |
| `adapty_Paywall_Start_Button_tap`, `storekit_Paywall_Start_Button_tap` | `Paywall_Start_Button_tap` |

## Property mapping

| Old property | New property |
|---|---|
| event name prefix `adapty_` / `storekit_` | `purchase_service` |
| `paywallID` | `paywall_id` |
| `placement` | `placement_id` |
| `productID` | `product_id` |
| `variationId` | `variation_id` |
| `presentationID` | `presentation_id` |
| `errorDomain` | `error_domain` |
| `errorCode` | `error_code` |
| `error` | `error_description` |
| `failedIdentifiers` | `failed_identifiers` |

## Notes for analytics

`paywall_shown` is the canonical clean event for real paywall presentation. It replaces `Paywall_Screen_view`, `PayWall_Screen_view`, and the `*_PaywallOpenEvent_*` family. `paywall_id` keeps the exact canonical string that previously appeared as the `PaywallOpenEvent_<id>` suffix, so old and new breakdowns map 1:1.

Old event names are stopped from version 2.0.7 and should be marked deprecated in Lexicon.
