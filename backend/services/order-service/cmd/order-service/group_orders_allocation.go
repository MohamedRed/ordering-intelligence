package main

import "sort"

func allocateGroupOrderPricing(items []orderItem, hostID string, taxCents, feeCents, discountCents int64) groupOrderPricing {
	byParticipant := map[string]int64{}
	for _, item := range items {
		pid := item.ParticipantID
		line := (item.PriceCents + orderItemModifiersSum(item)) * int64(item.Quantity)
		byParticipant[pid] += line
	}
	participants := make([]string, 0, len(byParticipant))
	for pid := range byParticipant {
		participants = append(participants, pid)
	}
	sort.Strings(participants)

	allocations := make([]groupOrderAllocation, 0, len(participants))
	totalSubtotal := int64(0)
	for _, subtotal := range byParticipant {
		totalSubtotal += subtotal
	}

	feeShares := allocateSharedAmount(byParticipant, hostID, feeCents, totalSubtotal, participants)
	taxShares := allocateSharedAmount(byParticipant, hostID, taxCents, totalSubtotal, participants)
	discountShares := allocateSharedAmount(byParticipant, hostID, discountCents, totalSubtotal, participants)

	total := int64(0)
	for _, pid := range participants {
		subtotal := byParticipant[pid]
		fee := feeShares[pid]
		tax := taxShares[pid]
		discount := discountShares[pid]
		lineTotal := subtotal + fee + tax - discount
		total += lineTotal
		allocations = append(allocations, groupOrderAllocation{
			ParticipantID: pid,
			SubtotalCents: subtotal,
			FeeCents:      fee,
			TaxCents:      tax,
			DiscountCents: discount,
			TotalCents:    lineTotal,
		})
	}

	return groupOrderPricing{
		SubtotalCents: totalSubtotal,
		TaxCents:      taxCents,
		FeeCents:      feeCents,
		DiscountCents: discountCents,
		TotalCents:    total,
		Allocations:   allocations,
	}
}

func allocateSharedAmount(subtotals map[string]int64, hostID string, amount int64, totalSubtotal int64, participants []string) map[string]int64 {
	shares := map[string]int64{}
	if amount == 0 || totalSubtotal == 0 {
		for pid := range subtotals {
			shares[pid] = 0
		}
		return shares
	}
	allocated := int64(0)
	for pid, subtotal := range subtotals {
		share := (amount * subtotal) / totalSubtotal
		shares[pid] = share
		allocated += share
	}
	remainder := amount - allocated
	if remainder != 0 {
		if _, ok := shares[hostID]; ok {
			shares[hostID] += remainder
		} else if len(participants) > 0 {
			shares[participants[0]] += remainder
		}
	}
	return shares
}
