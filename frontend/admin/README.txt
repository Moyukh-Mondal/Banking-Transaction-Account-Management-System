# Bank frontend database management page

## Files
- `admin-records.html`: the management page
- `admin-records.css`: responsive styling
- `admin-records.js`: table navigation, search, record list, and CRUD UI

## Install
Copy these three files into your existing frontend directory (or the same directory as your admin dashboard). Open `admin-records.html` through Live Server.

## Important: configure backend endpoints
Open `admin-records.js` and edit `API_BASE` and `ENDPOINTS` at the top to match your actual FastAPI routes. The defaults assume the API runs at `http://127.0.0.1:8000` and routes like `/api/branches`.

The list endpoint must return either:
- `[{ "branch_id": 1, "branch_name": "..." }]`
- `{ "data": [{ "branch_id": 1, "branch_name": "..." }] }`
- `{ "items": [...] }`

Create/update/delete defaults:
- POST `/api/<resource>`
- PUT `/api/<resource>/<primary-key>`
- DELETE `/api/<resource>/<primary-key>`

If your backend uses different response formats or route names, change the JS accordingly.

## Authentication
If your backend uses JWT, uncomment and adapt the token header code inside `request()` to match how your existing `auth.js` stores the token. Do not remove backend authorization checks.

## Safety notes
Transaction, fund transfer, loan payment, and audit log tables are read-only in this starter UI. Financial and audit data should normally be changed through dedicated, validated backend operations, not arbitrary row deletion.
The generic editor learns field names from existing records. If a table is empty, the Add form cannot infer its columns; create a schema-specific form for that table or add field definitions in the JS.
