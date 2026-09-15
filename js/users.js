/**
 * User Management Logic Module
 * Systems Analysis and Design — Lab 4
 */

/**
 * Fetch all user profiles (Admin Only)
 */
async function fetchUserProfiles() {
  const { data, error } = await supabaseClient
    .from('profiles')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    console.error("Error fetching user profiles:", error);
    throw error;
  }

  return data || [];
}

/**
 * Update User Role via RPC (Admin Only, prevents self-demotion)
 */
async function updateUserRoleRPC(targetUserId, newRole) {
  const { data, error } = await supabaseClient.rpc('update_user_role', {
    p_target_user_id: targetUserId,
    p_new_role: newRole
  });

  if (error) {
    console.error("RPC update_user_role error:", error);
    throw new Error(error.message || "Failed to update user role.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}
