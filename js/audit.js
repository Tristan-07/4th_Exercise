/**
 * Audit Trail Logging & Management Module
 * Systems Analysis and Design — Lab 4
 */

/**
 * Fetch Audit Logs with filters (For Administrator Audit Trail View)
 */
async function fetchAuditLogs({ actionFilter, searchKeyword } = {}) {
  let query = supabaseClient
    .from('audit_logs')
    .select(`
      *,
      user:user_id (full_name, email, role)
    `)
    .order('created_at', { ascending: false });

  if (actionFilter && actionFilter !== 'ALL') {
    query = query.eq('action', actionFilter);
  }

  if (searchKeyword && searchKeyword.trim()) {
    const kw = `%${searchKeyword.trim()}%`;
    query = query.ilike('description', kw);
  }

  const { data, error } = await query;

  if (error) {
    console.error("Error fetching audit logs:", error);
    throw error;
  }

  return data || [];
}

/**
 * Client-side audit logger helper
 */
async function logClientAuditEvent(action, module, recordId, description) {
  try {
    const user = await getCurrentUser();
    const userId = user ? user.id : null;

    const { error } = await supabaseClient.rpc('log_audit_event', {
      p_user_id: userId,
      p_action: action,
      p_module: module,
      p_record_id: recordId ? String(recordId) : null,
      p_description: description
    });

    if (error) {
      // Fallback insert if RPC fails
      await supabaseClient.from('audit_logs').insert([{
        user_id: userId,
        action: action,
        module: module,
        record_id: recordId ? String(recordId) : null,
        description: description
      }]);
    }
  } catch (err) {
    console.warn("Failed to write audit log:", err);
  }
}
