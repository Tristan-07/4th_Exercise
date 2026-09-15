/**
 * Borrowing, Approvals, Release & Returns Logic Module
 * Systems Analysis and Design — Lab 4
 */

/**
 * Fetch all equipment from database
 */
async function fetchEquipmentList() {
  const { data, error } = await supabaseClient
    .from('equipment')
    .select('*')
    .order('equipment_code', { ascending: true });

  if (error) {
    console.error("Error fetching equipment:", error);
    throw error;
  }
  return data || [];
}

/**
 * Fetch available equipment for borrowing request form
 */
async function fetchAvailableEquipment() {
  const { data, error } = await supabaseClient
    .from('equipment')
    .select('*')
    .eq('status', 'Available')
    .order('name', { ascending: true });

  if (error) {
    console.error("Error fetching available equipment:", error);
    throw error;
  }
  return data || [];
}

/**
 * Submit a new borrowing request (Starts as Pending)
 */
async function submitBorrowingRequest({ equipment_id, quantity, purpose, expected_return_date }) {
  const user = await getCurrentUser();
  if (!user) throw new Error("You must be logged in to submit a request.");

  // BR-A4-01 Validation: Verify equipment availability
  const { data: equip, error: equipErr } = await supabaseClient
    .from('equipment')
    .select('*')
    .eq('id', equipment_id)
    .single();

  if (equipErr || !equip) {
    throw new Error("Selected equipment was not found.");
  }

  if (equip.status !== 'Available') {
    throw new Error(`BR-A4-01 Violation: Equipment '${equip.name}' is currently ${equip.status} and cannot be requested.`);
  }

  if (quantity <= 0 || quantity > equip.quantity) {
    throw new Error(`Requested quantity (${quantity}) exceeds available stock (${equip.quantity}).`);
  }

  if (!purpose || !purpose.trim()) {
    throw new Error("Purpose of borrowing is required.");
  }

  if (!expected_return_date) {
    throw new Error("Expected return date is required.");
  }

  const { data, error } = await supabaseClient
    .from('borrowing_requests')
    .insert([{
      requester_id: user.id,
      equipment_id: equipment_id,
      quantity: parseInt(quantity, 10),
      purpose: purpose.trim(),
      expected_return_date: expected_return_date,
      status: 'Pending'
    }])
    .select();

  if (error) {
    console.error("Error creating borrowing request:", error);
    throw error;
  }

  const createdRequest = data[0];

  // Log Audit Event for Request Creation
  if (typeof logClientAuditEvent === 'function') {
    await logClientAuditEvent('CREATED', 'Borrowing', createdRequest.id, `Submitted borrowing request for equipment: ${equip.name} (Qty: ${quantity}).`);
  }

  return createdRequest;
}

/**
 * Fetch borrowing requests submitted by current user
 */
async function fetchMyBorrowingRequests() {
  const user = await getCurrentUser();
  if (!user) return [];

  const { data, error } = await supabaseClient
    .from('borrowing_requests')
    .select(`
      *,
      equipment:equipment_id (equipment_code, name, category, status)
    `)
    .eq('requester_id', user.id)
    .order('created_at', { ascending: false });

  if (error) {
    console.error("Error fetching user borrowing requests:", error);
    throw error;
  }

  return data || [];
}

/**
 * Fetch all borrowing requests (For Admin / Approvals / Records page)
 */
async function fetchAllBorrowingRequests() {
  const { data, error } = await supabaseClient
    .from('borrowing_requests')
    .select(`
      *,
      equipment:equipment_id (equipment_code, name, category, status),
      requester:requester_id (full_name, email, role)
    `)
    .order('created_at', { ascending: false });

  if (error) {
    console.error("Error fetching all borrowing requests:", error);
    throw error;
  }

  return data || [];
}

/**
 * Fetch Released borrowing requests (For Returns processing page)
 */
async function fetchReleasedRequests() {
  const { data, error } = await supabaseClient
    .from('borrowing_requests')
    .select(`
      *,
      equipment:equipment_id (equipment_code, name, category, status),
      requester:requester_id (full_name, email, role)
    `)
    .eq('status', 'Released')
    .order('released_at', { ascending: false });

  if (error) {
    console.error("Error fetching released requests:", error);
    throw error;
  }

  return data || [];
}

/**
 * Approve borrowing request via RPC (Enforces BR-A4-01, BR-A4-02, BR-A4-03)
 */
async function approveRequestRPC(requestId) {
  const { data, error } = await supabaseClient.rpc('approve_borrowing_request', {
    p_request_id: requestId
  });

  if (error) {
    console.error("RPC approve_borrowing_request error:", error);
    throw new Error(error.message || "Approval failed.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Reject borrowing request via RPC
 */
async function rejectRequestRPC(requestId, reason) {
  const { data, error } = await supabaseClient.rpc('reject_borrowing_request', {
    p_request_id: requestId,
    p_reason: reason
  });

  if (error) {
    console.error("RPC reject_borrowing_request error:", error);
    throw new Error(error.message || "Rejection failed.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Release Approved Borrowing Request via RPC (BR-A4-04, BR-A4-05, BR-A4-07)
 */
async function releaseRequestRPC(requestId) {
  const { data, error } = await supabaseClient.rpc('release_borrowing_request', {
    p_request_id: requestId
  });

  if (error) {
    console.error("RPC release_borrowing_request error:", error);
    throw new Error(error.message || "Release operation failed.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Process Return for Released Borrowing Request via RPC (BR-A4-06, BR-A4-08)
 */
async function returnRequestRPC(requestId, condition, remarks) {
  const { data, error } = await supabaseClient.rpc('return_borrowing_request', {
    p_request_id: requestId,
    p_condition: condition,
    p_remarks: remarks || ''
  });

  if (error) {
    console.error("RPC return_borrowing_request error:", error);
    throw new Error(error.message || "Return processing failed.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}
