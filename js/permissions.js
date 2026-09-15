/**
 * Permissions & Role Access Control Matrix
 * Roles: administrator, laboratory_staff, requester
 */

const ROLES = {
  ADMIN: 'administrator',
  STAFF: 'laboratory_staff',
  REQUESTER: 'requester'
};

// Page access permission mapping per role
const PAGE_PERMISSIONS = {
  'dashboard.html': [ROLES.ADMIN, ROLES.STAFF, ROLES.REQUESTER],
  'equipment.html': [ROLES.ADMIN, ROLES.STAFF, ROLES.REQUESTER],
  'borrowing.html': [ROLES.ADMIN, ROLES.STAFF, ROLES.REQUESTER],
  'requests.html': [ROLES.ADMIN, ROLES.STAFF, ROLES.REQUESTER],
  'approvals.html': [ROLES.ADMIN],
  'returns.html': [ROLES.ADMIN, ROLES.STAFF],
  'maintenance.html': [ROLES.ADMIN, ROLES.STAFF],
  'users.html': [ROLES.ADMIN],
  'reports.html': [ROLES.ADMIN],
  'audit-logs.html': [ROLES.ADMIN]
};

function hasRole(userRole, targetRole) {
  return userRole === targetRole;
}

function canAccessPage(userRole, pageName) {
  // Extract filename from path (e.g. /Lab-4/dashboard.html -> dashboard.html)
  const page = pageName.split('/').pop() || 'dashboard.html';
  const allowedRoles = PAGE_PERMISSIONS[page];
  if (!allowedRoles) return true; // Unrestricted page
  return allowedRoles.includes(userRole);
}

function canApprove(role) {
  return role === ROLES.ADMIN;
}

function canRelease(role) {
  return role === ROLES.ADMIN;
}

function canReturn(role) {
  return role === ROLES.ADMIN || role === ROLES.STAFF;
}

function canManageEquipment(role) {
  return role === ROLES.ADMIN;
}

function canManageUsers(role) {
  return role === ROLES.ADMIN;
}

function canViewAuditLogs(role) {
  return role === ROLES.ADMIN;
}
