/**
 * Equipment Management Logic Module (CRUD)
 * Systems Analysis and Design — Lab 4
 */

/**
 * Create Equipment via RPC (Admin Only)
 */
async function createEquipmentRPC(code, name, category, quantity, condition, laboratory) {
  const { data, error } = await supabaseClient.rpc('create_equipment', {
    p_code: code,
    p_name: name,
    p_category: category,
    p_quantity: parseInt(quantity, 10),
    p_condition: condition,
    p_laboratory: laboratory
  });

  if (error) {
    console.error("RPC create_equipment error:", error);
    throw new Error(error.message || "Failed to create equipment.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Update Equipment via RPC (Admin Only)
 */
async function updateEquipmentRPC(id, code, name, category, quantity, condition, laboratory, status) {
  const { data, error } = await supabaseClient.rpc('update_equipment', {
    p_id: id,
    p_code: code,
    p_name: name,
    p_category: category,
    p_quantity: parseInt(quantity, 10),
    p_condition: condition,
    p_laboratory: laboratory,
    p_status: status
  });

  if (error) {
    console.error("RPC update_equipment error:", error);
    throw new Error(error.message || "Failed to update equipment.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}

/**
 * Delete Equipment via RPC (Admin Only - checks active borrowings)
 */
async function deleteEquipmentRPC(id) {
  const { data, error } = await supabaseClient.rpc('delete_equipment', {
    p_id: id
  });

  if (error) {
    console.error("RPC delete_equipment error:", error);
    throw new Error(error.message || "Failed to delete equipment.");
  }

  if (!data.success) {
    throw new Error(data.message);
  }

  return data;
}
