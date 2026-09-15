/**
 * Centralized Authentication & Authorization Module
 */

let cachedProfile = null;
let cachedUser = null;

/**
 * Log in user using Supabase Auth and retrieve profile
 */
async function loginUser(email, password) {
  if (!supabaseClient) {
    throw new Error("Supabase client is not initialized.");
  }

  const { data, error } = await supabaseClient.auth.signInWithPassword({
    email: email.trim(),
    password: password
  });

  if (error) {
    throw error;
  }

  const user = data.user;
  cachedUser = user;

  // Retrieve user profile from public.profiles
  const profile = await fetchUserProfile(user.id);
  cachedProfile = profile;

  // Log Audit Event for LOGIN
  if (typeof logClientAuditEvent === 'function') {
    await logClientAuditEvent('LOGIN', 'Auth', user.id, `User ${profile.email} authenticated as ${profile.role}.`);
  }

  return { user, profile };
}

/**
 * Fetch profile record from public.profiles
 */
async function fetchUserProfile(userId) {
  // 1. Try fetching profile by exact auth user ID
  let { data, error } = await supabaseClient
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .maybeSingle();

  // 2. Fallback: If not found by ID, try fetching by email
  if (!data) {
    const userRes = await supabaseClient.auth.getUser();
    const user = userRes?.data?.user;

    if (user && user.email) {
      const { data: emailProfile } = await supabaseClient
        .from('profiles')
        .select('*')
        .eq('email', user.email.trim())
        .maybeSingle();

      if (emailProfile) {
        data = emailProfile;
        // Sync ID in profiles table to match auth.users ID
        try {
          await supabaseClient
            .from('profiles')
            .update({ id: userId })
            .eq('email', user.email.trim());
          data.id = userId;
        } catch (syncErr) {
          console.warn("Could not auto-sync profile ID:", syncErr);
        }
      }
    }
  }

  // 3. Fallback if profile is still missing
  if (!data) {
    console.warn("Profile not found in database, creating fallback profile representation.");
    const user = (await supabaseClient.auth.getUser())?.data?.user;
    const email = user?.email || '';
    let role = user?.user_metadata?.role || ROLES.REQUESTER;

    if (email.startsWith('admin@')) {
      role = ROLES.ADMIN;
    } else if (email.startsWith('staff@')) {
      role = ROLES.STAFF;
    }

    return {
      id: userId,
      full_name: user?.user_metadata?.full_name || email || 'User',
      email: email,
      role: role
    };
  }

  return data;
}

/**
 * Sign out user and redirect to login page
 */
async function logoutUser() {
  if (typeof logClientAuditEvent === 'function' && cachedUser) {
    await logClientAuditEvent('LOGOUT', 'Auth', cachedUser.id, `User signed out.`);
  }

  if (supabaseClient) {
    await supabaseClient.auth.signOut();
  }
  cachedProfile = null;
  cachedUser = null;
  window.location.href = 'login.html';
}

/**
 * Get current authenticated user
 */
async function getCurrentUser() {
  if (cachedUser) return cachedUser;
  if (!supabaseClient) return null;
  
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) return null;
  
  cachedUser = session.user;
  return cachedUser;
}

/**
 * Get current user profile
 */
async function getCurrentProfile() {
  if (cachedProfile) return cachedProfile;
  const user = await getCurrentUser();
  if (!user) return null;

  cachedProfile = await fetchUserProfile(user.id);
  return cachedProfile;
}

/**
 * Enforce authentication on protected pages.
 * Redirects to login.html if unauthenticated.
 */
async function requireAuth() {
  if (!supabaseClient) return null;

  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    console.warn("Unauthenticated session detected. Redirecting to login.html.");
    window.location.href = 'login.html';
    return null;
  }

  cachedUser = session.user;
  cachedProfile = await fetchUserProfile(session.user.id);

  return { user: cachedUser, profile: cachedProfile };
}

/**
 * Enforce role-based access control on current page.
 */
async function requireRole(allowedRoles) {
  const authData = await requireAuth();
  if (!authData) return null;

  const { profile } = authData;
  const currentPage = window.location.pathname.split('/').pop() || 'dashboard.html';

  const isAllowed = allowedRoles.includes(profile.role) && canAccessPage(profile.role, currentPage);

  if (!isAllowed) {
    showAccessDeniedModal(profile.role);
    return null;
  }

  // Render header details & sidebar navigation upon valid authorization
  renderHeaderUserBadge(profile);
  renderSidebarNav(profile.role, currentPage);

  return authData;
}

/**
 * Display Access Denied modal and redirect user to their dashboard
 */
function showAccessDeniedModal(currentRole) {
  const overlay = document.createElement('div');
  overlay.className = 'access-denied-overlay';
  overlay.innerHTML = `
    <div class="access-denied-box">
      <h3>Access Denied</h3>
      <p>You do not have permission to view this page. Redirecting to your dashboard...</p>
      <button class="btn btn-primary" onclick="window.location.href='dashboard.html'">Return to Dashboard</button>
    </div>
  `;
  document.body.appendChild(overlay);

  setTimeout(() => {
    window.location.href = 'dashboard.html';
  }, 2500);
}

/**
 * Render Header User Info Badge
 */
function renderHeaderUserBadge(profile) {
  const badgeContainer = document.getElementById('userProfileBadge');
  if (!badgeContainer) return;

  const roleLabel = profile.role.replace('_', ' ');

  badgeContainer.innerHTML = `
    <div class="user-details">
      <div class="user-name">${escapeHTML(profile.full_name || profile.email)}</div>
      <span class="user-role-tag role-${profile.role}">${escapeHTML(roleLabel)}</span>
    </div>
    <button class="btn btn-secondary" onclick="logoutUser()">Logout</button>
  `;
}

/**
 * Render dynamic sidebar navigation based on role
 */
function renderSidebarNav(role, activePage) {
  const sidebarNavContainer = document.getElementById('sidebarNav');
  if (!sidebarNavContainer) return;

  let navItems = [];

  if (role === ROLES.ADMIN) {
    navItems = [
      { label: 'Dashboard', page: 'dashboard.html', icon: '📊' },
      { label: 'Users', page: 'users.html', icon: '👥' },
      { label: 'Equipment', page: 'equipment.html', icon: '📦' },
      { label: 'Borrowing Requests', page: 'borrowing.html', icon: '📋' },
      { label: 'Approvals', page: 'approvals.html', icon: '✅' },
      { label: 'Returns', page: 'returns.html', icon: '🔄' },
      { label: 'Maintenance', page: 'maintenance.html', icon: '🛠️' },
      { label: 'Reports', page: 'reports.html', icon: '📈' },
      { label: 'Audit Logs', page: 'audit-logs.html', icon: '📜' }
    ];
  } else if (role === ROLES.STAFF) {
    navItems = [
      { label: 'Dashboard', page: 'dashboard.html', icon: '📊' },
      { label: 'Equipment', page: 'equipment.html', icon: '📦' },
      { label: 'Borrowing', page: 'borrowing.html', icon: '📋' },
      { label: 'Returns', page: 'returns.html', icon: '🔄' },
      { label: 'Maintenance', page: 'maintenance.html', icon: '🛠️' }
    ];
  } else {
    // Requester / Viewer
    navItems = [
      { label: 'Dashboard', page: 'dashboard.html', icon: '📊' },
      { label: 'Available Equipment', page: 'equipment.html', icon: '📦' },
      { label: 'My Requests', page: 'requests.html', icon: '📑' },
      { label: 'Request History', page: 'borrowing.html', icon: '📜' }
    ];
  }

  let html = '';
  navItems.forEach(item => {
    const isActive = activePage === item.page ? 'class="active"' : '';
    html += `<li><a href="${item.page}" ${isActive}><span>${item.icon}</span> <span>${item.label}</span></a></li>`;
  });

  html += `<li><a href="#" onclick="logoutUser(); return false;"><span>🚪</span> <span>Logout</span></a></li>`;

  sidebarNavContainer.innerHTML = html;
}

/**
 * Utility HTML sanitizer
 */
function escapeHTML(str) {
  if (!str) return '';
  return str.replace(/[&<>'"]/g, 
    tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
  );
}
