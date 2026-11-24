# B.R. Edible Oils Pvt. Ltd. - Factory ERP (Flutter + Firebase)
One app for Android, Windows and Web. Firebase project: **b-r-edible-oil-pvt-ltd** (free Spark plan).

## IMPORTANT - honest status
This is **source code only. It has NOT been compiled or run** (no Flutter SDK was available where it was written).
Expect a few small compile errors on the first build - copy the error text and send it for a fix.
Firestore rules are also untested (no emulator run). Test with dummy data before real use.

## Logins (roles)
| Role | What they can do |
|---|---|
| admin | Everything + Users, Company settings, Role permissions, Backup/Restore, void entries, edit QC/expense/payment records |
| manager | Everything except admin-only screens (can be restricted further by admin) |
| accountant | Purchase, sales, shipments, expenses, reports, suppliers/customers (editable by admin) |
| operator | Production, inventory, tanks, QC, attendance entry (editable by admin) |
| **employee** | **Only enters attendance** (staff + labour) for today. Cannot edit, cannot see salaries or any other screen |
| **driver** | **Only sees shipments assigned to him.** Can start trip (shares GPS) and mark "delivered". Nothing else |

Create all logins in **Users & Roles** (admin). Employee/Labour *master records* (salary, wage) are in **Masters**.

## Shipments & live tracking
1. Create the GST invoice, then **Shipments & Tracking > New shipment**: pick invoice + driver (a user with role driver).
2. Driver opens the app > taps the shipment > **Start trip & share my location**. GPS is sent about every 20 s (Android keeps
   running with a notification). Driver taps **Mark delivered successfully** at the end - this is the only thing he can update.
3. Admin sees the map (OpenStreetMap) and taps **Share tracking link with customer** (WhatsApp/copy). The customer opens
   the link, sees a live map and status, no login needed. The link contains a long random id; anyone with the link can view that one shipment.

### Publish the web app (needed for the customer tracking link)
- Download the **Web-App** artifact from GitHub (see below) and put its files in a folder `build/web`, install Node.js, then in the project folder run:
  `npm install -g firebase-tools`, `firebase login`, `firebase deploy --only hosting,firestore:rules`
- Your site will be `https://br-industriestonk.web.app` (Company Settings > "Website address for customer tracking links" must match).
- Optional automation: run `firebase login:ci` once, add the printed token as a GitHub repository secret named `FIREBASE_TOKEN`; each build then publishes automatically.

## Build on GitHub (no Flutter needed)
1. Create a free **private** GitHub repository.
2. Firebase console > Project settings > Add app > **Android**, package name `com.bredible_erp`.
   Copy the App ID (looks like `1:893650543343:android:xxxx`) and put it in `lib/firebase_options.dart` (Android appId).
3. Upload **everything** in this folder (check `.github/workflows/build.yml` is there). Commit.
4. Actions tab > "Build ERP apps" (10-15 min). Download **Android-APK**, **Windows-App**, **Web-App**.
5. Windows: unzip, run `br_edible_oils_erp.exe`. Android: copy APK to phone and install (allow unknown apps).
The workflow adds the Android internet + location permissions automatically (`tools/patch_android.py`).

## App name and icon
The app is called **B.R. Edible Oils** and uses your company emblem as its icon on Android (home screen), Windows (exe/taskbar)
and the web app (browser tab / "Install app"). The icon file is `assets/app_icon.png` (1024x1024). To change it, replace that file
and rebuild. The build does this automatically (`icons_*.yaml`, `tools/brand.py`).

## Install as an app
- **Android:** download Android-APK from the GitHub run, copy to the phone, open it, allow "install unknown apps". (It is signed with a
  debug key - fine for your own phones, not for Play Store.)
- **Windows:** download Windows-App, unzip, keep the whole folder together, right-click `br_edible_oils_erp.exe` > Send to > Desktop (shortcut).
- **Web:** open your site (`https://br-industriestonk.web.app`) in Chrome/Edge > menu > Install app / Add to Home screen.

## New: Import & Opening Stock (Admin)
Menu > **Import & Opening Stock**: (1) enter the stock you already have in each godown / tank as *Opening stock*;
(2) import old Suppliers, Customers, Employees, Labour, old Expenses and old Supplier payments from a CSV file (made in Excel).
Old purchases / production / invoices are not bulk-imported because they change stock and GST numbering.
Settings > **Check database connection** shows which Firebase project the app uses and whether it can reach it.

## Admin can add / edit / remove everything
- Masters (suppliers, customers, employees, labour, machines, godowns, tanks), users: add, edit, **delete** (red bin icon). A godown with stock or a tank with oil cannot be deleted. Deleting a user removes the app profile; also remove the login in Firebase > Authentication if wanted.
- Expenses, supplier payments, QC, attendance (staff + labour): edit and delete.
- Purchases, DOC purchases, production: **Void** (undo icon, stock is reversed) -> then **Delete** (bin) if you want it gone. Cancelled invoices: **Delete cancelled invoice**. Payroll: **Unlock this month**.
- Shipments: **Change driver / vehicle**, **Remove shipment**.
- Every delete keeps a copy of the details in the Audit trail. No demo data is installed: only the factory structure (10 machines, 6 godowns, 7 tanks) you can rename or delete.

## Driver location & Google Maps
The driver app asks for Location permission as soon as it opens (and shows a banner with a button if it is off or blocked).
Driver: **Navigate in Google Maps** to the customer address. Admin and customer: live pin on a map in the app and **Open in Google Maps**.
(A Google map drawn inside the app needs a Google Maps API key with billing enabled; not used.)

## Firebase console (once)
1. Authentication > Get started > Email/Password ON.
2. Firestore Database > Create (production mode, Mumbai). Stay on the **free Spark plan**.
3. Firestore > Rules > paste all of `firestore.rules` > Publish (**republish every time this file changes**).
4. Open the app > "First time? Set up the Admin account" - do this immediately (setup closes after the first admin).

## What is editable by the admin
Company details, invoice series, oil density, expense categories, PF/ESI rates, tracking website address, role permissions,
all masters (suppliers, customers, employees, labour, machines, godowns, tanks), users/roles/disable, QC/expense/payment corrections
(every change is logged old -> new in the audit trail). Purchases and production entries that affect stock are **voided** (record kept,
stock reversed) and re-entered - they are never silently edited or deleted. Invoices are cancelled with reason (stock returned).

## Features
Purchase (seed + DOC) - supplier payments - production (10 machines, shifts, yield, wastage) - inventory & Khali - 7 oil tanks -
QC - GST invoices (CGST/SGST/IGST, auto numbering, PDF, share/print) - shipments & tracking - staff attendance - labour attendance -
payroll (PF/ESI) - labour wages - expenses - reports (+PDF) - TallyPrime XML export - backup & restore - audit trail - dark/light theme -
offline entry (syncs later; creating an invoice needs internet).

## Still NOT included / limits (honest)
- **E-invoice IRN and e-way bill are not generated.** You type the numbers you got from the GST portal into the invoice; they print on the PDF.
- Weighment-slip photos (Firebase Storage needs the paid plan) - type the slip number instead.
- TDS; leave balances (leave is an attendance status); TallyPrime export untested against real Tally.
- Role permissions hide screens in the app; the database rules enforce the *role level* only (admin/manager/accountant/operator/employee/driver).
- Location tracking on Android works with screen off (foreground notification) but depends on phone battery settings; drivers must keep GPS + internet on.
- Restore adds back only missing records and cannot recreate login passwords.
- Customer link uses free OpenStreetMap tiles (light use only).

## Build on your own PC instead (optional)
Install Flutter + Node.js, then double-click `SETUP_WINDOWS.bat` and run `flutter run -d windows`.
