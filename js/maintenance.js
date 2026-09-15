/**
 * Equipment Maintenance Management Logic Module
 * Systems Analysis and Design — Lab 4
 */

/**
 * Fetch all maintenance requests (Staff & Admin)
 */
async function fetchMaintenanceRequests() {
  const { data, error } = await supabaseClient
    .from('maintenance_requests')
    .select(`
      *,
      equipment:equipment_id (equipment_code, name, category, status, laboratory),
      reporter:reported_by (full_name, email, role),
      resolver:resolved_by (full_name, email)
    `)
    .order('created_at', { ascending: false });

  if (error) {
    console.error("Error fetching maintenance requests:", error);
    throw error;
  }

  return data || [];
}

/**
 * Submit Maintenance Request via RPC (Staff Only)
 */
async function submitMaintenanceRequestRPC(equipmentId, description) {
  const { data, error } = await supabaseClient.rpc('submit_maintenance_request', {
    p_equipment_id: equipmentId,
    p_description: description
  });

  if (error) {
    console.error("RPC submit_maintenance_request error:", error);
    throw new Error(error.message || "Failed to submit maintenance request.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Start Equipment Maintenance via RPC (Admin Only)
 */
async function startMaintenanceRPC(maintenanceId) {
  const { data, error } = await supabaseClient.rpc('start_equipment_maintenance', {
    p_maintenance_id: maintenanceId
  });

  if (error) {
    console.error("RPC start_equipment_maintenance error:", error);
    throw new Error(error.message || "Failed to start maintenance.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Complete Equipment Maintenance via RPC (Admin Only)
 */
async function completeMaintenanceRPC(maintenanceId, targetStatus, notes) {
  const { data, error } = await supabaseClient.rpc('complete_equipment_maintenance', {
    p_maintenance_id: maintenanceId,
    p_target_status: targetStatus,
    p_notes: notes || 'Maintenance completed'
  });

  if (error) {
    console.error("RPC complete_equipment_maintenance error:", error);
    throw new Error(error.message || "Failed to complete maintenance.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}
