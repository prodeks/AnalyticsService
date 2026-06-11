# Аналитика: покупки и пейволы


Все события уходят одновременно в **Firebase, Facebook, AppsFlyer и Mixpanel**.
У каждого события есть приставка источника покупки:

- `adapty_` — покупки через Adapty (основной вариант)
- `storekit_` — прямые покупки через App Store (для Китая)

События одного показа пейвола связаны между собой через `presentationID`, поэтому воронку видно целиком.

---

## Показ экрана

| Событие | Когда срабатывает |
|---|---|
| `PaywallOpenEvent_<id>` | Пользователь увидел экран с подпиской |
| `PaywallClosedEvent_<id>` | Пользователь закрыл экран (с пометкой, была ли покупка) |
| `Onboarding_Started` | Начался онбординг (верхняя точка воронки) |

## Воронка покупки

| Событие | Когда срабатывает |
|---|---|
| `paywall_checkout_initiated` | Нажата кнопка покупки, до окна оплаты Apple |
| `Paywall_Start_Button_tap` | Дублирующее событие для воронки |
| `paywall_checkout_cancelled` | Пользователь закрыл окно оплаты |

## Результат покупки

| Событие | Когда срабатывает |
|---|---|
| `sale_confirmation_success` | Оплата прошла (сюда же уходит выручка в Facebook) |
| `sale_confirmation_cancel` | Пользователь отменил оплату |
| `sale_confirmation_fail` | Ошибка при оплате |
| `sale_confirmation_restore` | Пользователь восстановил подписку |

### Пример успешной покупки

```
Открытие пейвола
  → Начат чекаут
  → Покупка успешна (+ выручка в Facebook)
  → Закрытие пейвола (куплено: да)
```

Если отмена — вместо успеха: «Покупка отменена» + «Чекаут отменён».
Если ошибка — «Покупка не удалась» + «Ошибка покупки» с деталями.

---

## Ошибки (для диагностики)

| Событие | Когда срабатывает |
|---|---|
| `purchaseFailed` | Покупка не прошла (не считая обычной отмены) |
| `restoreFailed` | Не удалось восстановить покупки |
| `pricesFailed` | Не загрузились цены из App Store |
| `paywallFailed` | Пейвол не удалось показать |
| `paywall_fetch_error` | Не удалось загрузить пейвол из сети |

---

## Параметры событий

### Общие параметры (показ и покупки)

| Параметр | Описание |
|---|---|
| `paywallID` | ID пейвола |
| `placement` | Площадка/точка, откуда показан пейвол или начата покупка |
| `productID` / `product_id` | ID товара |
| `price` / `value` | Цена товара |
| `currency` | Валюта |
| `variationId` | ID варианта A/B-теста |
| `presentationID` | ID конкретного показа (для связи событий) |
| `purchased` | Была ли покупка при закрытии экрана (да/нет) |

### Параметры ошибок

| Параметр | Описание |
|---|---|
| `reason` | Категория ошибки (см. справочник ниже) |
| `error` / `error_description` | Текстовое описание ошибки |
| `errorDomain` | Техническая область ошибки (`AdaptyError`, `SKErrorDomain` и т.д.) |
| `errorCode` | Числовой код ошибки |
| `failedIdentifiers` | Список ID товаров, которые не загрузились (для `pricesFailed`) |

**Какие параметры в каком событии ошибки:**

| Событие | Параметры |
|---|---|
| `purchaseFailed` | `reason`, `productID`, `placement`, `errorDomain`, `errorCode`, `price`, `currency`, `paywallID`, `presentationID`, `variationId` |
| `restoreFailed` | `reason`, `errorDomain`, `errorCode` |
| `pricesFailed` | `reason`, `error`, `errorDomain`, `errorCode`, `failedIdentifiers` |
| `paywallFailed` | `placement`, `reason`, `error`, `errorDomain`, `errorCode` |
| `paywall_fetch_error` | `placement`, `error`, `errorDomain`, `errorCode` |

---

## Справочник причин ошибок (`reason`)

### Покупки и восстановление

| Значение | Что означает |
|---|---|
| `cancelled` | Пользователь отменил оплату |
| `network_error` | Проблема с сетью |
| `payment_invalid` | Оплата невозможна/некорректна |
| `storekit_sync_failed` | Не удалось синхронизироваться с App Store |

### Показ и загрузка пейвола

| Значение | Что означает |
|---|---|
| `missing_product_identifiers` | В настройках не указаны ID товаров |
| `invalid_product_identifiers` | ID товаров указаны, но не найдены в App Store |
| `missing_paywall_data` | Adapty не вернул данные пейвола |
| `custom_view_unavailable` | Кастомный экран не удалось создать |
| `unconfigured_placement` | Запрошена ненастроенная площадка |
| `missing_view_identifier` | Не удалось определить экран для площадки |
| `products_not_loaded` | Пейвол запросили до загрузки товаров |
| `network_error` | Проблема с сетью |
| `storekit_error` | Ошибка App Store / StoreKit |
| `unknown` | Неизвестная ошибка |

### Внутренние коды ошибок (`errorCode`)

Собственные коды (отрицательные, чтобы не пересекаться с кодами Apple/Adapty):

| Код | Что означает |
|---|---|
| -1 | Не указаны ID товаров |
| -2 | ID товаров не совпадают с App Store |
| -101 | Adapty не вернул данные пейвола |
| -102 | Не создался кастомный экран |
| -103 | Площадка не настроена |
| -104 | Не определён экран для площадки |
| -105 | Товары ещё не загружены |

Положительные коды приходят напрямую от Apple (`SKErrorDomain`) или Adapty (`AdaptyError`).
