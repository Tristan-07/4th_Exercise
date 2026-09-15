# Systems Analysis and Design — Laboratory 4
## Role-Based Asset Transaction and Approval Management

### Overview
This web application implements Laboratory 4 of Systems Analysis and Design, establishing a role-based laboratory asset transaction and approval management system with database-level Row Level Security (RLS), atomic workflow transitions, maintenance tracking, and an immutable audit trail.

### Technology Stack
- **Frontend:** HTML5, CSS3, Vanilla JavaScript (No frameworks, Node.js, or PHP)
- **Backend Service:** Supabase (Auth, PostgreSQL Database, Row Level Security, Stored RPC Procedures)
- **Hosting:** GitHub Pages (Pure static site deployment)

---

### User Roles & Permissions Matrix
| Function / Module | Administrator | Laboratory Staff | Requester / Viewer |
| :--- | :---: | :---: | :---: |
| **Dashboard** | Full Metrics | Operational View | Personal History |
| **Equipment Catalog** | Full Management (CRUD) | View & Request | View Available Items |
| **Submit Request** | Yes | Yes | Yes |
| **View Own Requests** | Yes | Yes | Yes |
| **View All Requests** | Yes | Yes | No |
| **Approve / Reject Requests** | Yes | No (Blocked) | No (Blocked) |
| **Release Equipment** | Yes | Yes | No (Blocked) |
| **Process Returns** | Yes | Yes | No (Blocked) |
| **Maintenance Management** | Approve / Resolve | Submit Requests | No |
| **User Management** | Assign Roles | No | No |
| **Reports & Analytics** | Full Summary | No | No |
| **Audit Logs** | View Immutable Logs | No | No |

---

### Borrowing Approval & Transaction Workflow
```text
Borrowing Request Submitted
         │
         ▼
      Pending ────────► Rejected (Reason Logged)
         │
         ▼
      Approved
         │
         ▼
      Released  (Equipment status = Borrowed)
         │
         ▼
      Returned  (Equipment status = Available [Good] OR Damaged [Damaged])
         │
         ▼
       Closed
```

---

### Enforced Business Rules
- **BR-A4-01:** Only Available equipment may be requested.
- **BR-A4-02:** Laboratory Staff and Administrators cannot approve their own borrowing requests.
- **BR-A4-03:** Only Administrators may approve or reject borrowing requests.
- **BR-A4-04:** Only Approved requests may be released.
- **BR-A4-05:** Released equipment becomes `Borrowed`.
- **BR-A4-06:** Returned equipment becomes `Available` (if Good) or `Damaged` (if Damaged).
- **BR-A4-07:** Rejected requests cannot be released.
- **BR-A4-08:** Returned transactions cannot be processed twice.
- **BR-A4-09:** Equipment under `Maintenance` cannot be requested or released.
- **BR-A4-10:** Sensitive operations (`LOGIN`, `LOGOUT`, `CREATED`, `APPROVED`, `REJECTED`, `RELEASED`, `RETURNED`, `MAINTENANCE_REQUESTED`) are logged in an immutable audit trail (`audit_logs`).

---

### Database Setup Instructions (Supabase)
1. Log into your Supabase Dashboard project (`kfbolysjloxvauqrxtye`).
2. Open the **SQL Editor** tab.
3. Paste and execute the contents of [`schema.sql`](file:///c:/xampp/htdocs/Lab-4/schema.sql).
4. Verify under **Table Editor** that `profiles`, `equipment`, `borrowing_requests`, `maintenance_requests`, and `audit_logs` are created with RLS enabled.

---

### GitHub Pages Deployment Instructions
1. Commit all files in the repository root.
2. Push the main branch to GitHub.
3. In your GitHub repository, go to **Settings** → **Pages**.
4. Select `Deploy from a branch` and set the source branch to `main` / `root`.
5. Click **Save**. The static application will deploy automatically to your GitHub Pages URL.

---

### Project Structure
```text
/
├── index.html            # Landing session redirector
├── login.html            # Authentication interface
├── dashboard.html        # Role-based metrics dashboard
├── equipment.html        # Equipment catalog & CRUD management
├── borrowing.html        # Borrowing records & equipment release
├── requests.html         # Requester borrowing submission & status
├── approvals.html        # Administrator approval queue
├── returns.html          # Equipment returns processing
├── maintenance.html      # Equipment maintenance management
├── users.html            # Administrator user role management
├── reports.html          # System analytics & summary reports
├── audit-logs.html       # Immutable audit logs interface
├── schema.sql            # Complete Supabase PostgreSQL DDL & RPCs
├── css/
│   └── style.css         # Responsive global CSS stylesheet
└── js/
    ├── supabase-config.js# Supabase client setup
    ├── permissions.js    # Role permissions matrix
    ├── auth.js           # Auth & session management
    ├── borrowing.js      # Borrowing & release RPC logic
    ├── maintenance.js    # Maintenance RPC logic
    ├── equipment-mgmt.js # Equipment CRUD RPC logic
    ├── users.js          # User management RPC logic
    ├── audit.js          # Audit logging helper
    └── reports.js        # Analytics metrics query engine
```
